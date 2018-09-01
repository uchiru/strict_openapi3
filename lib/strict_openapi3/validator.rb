require 'open-uri'

module StrictOpenapi3
  class Validator
    attr_reader :spec

    def initialize(target)
      @target = target
    end

    def validate_request(method, path, params, content_type, body)
      try_fetch_spec
      raise BrokenSchemaError.new(@schema_error) if @schema_error
      
      # find path spec
      unless path_spec = find_path(path)
        raise RequestValidationError.new(%(Not found spec for "#{path}"))
      end
      
      # find method spec
      unless meth_spec = path_spec["path"][method.downcase]
        raise RequestValidationError.new(%(Not found spec for "#{path}" "#{method.downcase}"))
      end

      # validate params
      all_params = extract_path_params(path, path_spec).merge(params)
      all_params.each do |name, value|
        param_spec = meth_spec["parameters"].find { |p| p["name"] == name }
        if param_spec
          if param_spec["schema"]["type"] == "integer" && !(value.to_s =~ /^[1-9][0-9]*$/)
            raise RequestValidationError.new(%(Expect integer param "#{name}" but get "#{value}" for "#{path}" "#{method.downcase}"))
          elsif param_spec["schema"]["type"] == "boolean" && ["true", "false"].index(value.to_s.downcase).nil?
            raise RequestValidationError.new(%(Expect boolean param "#{name}" but get "#{value}" for "#{path}" "#{method.downcase}"))
          end
        else
          raise RequestValidationError.new(%(Unknown param "#{name}" for "#{path}" "#{method.downcase}"))
        end
      end
      req_param_names = meth_spec["parameters"].select { |p| p["required"] }.map { |p| p["name"] }
      if (req_param_names - all_params.keys).length > 0
        raise RequestValidationError.new(%(Missed required params #{(req_param_names - all_params.keys).inspect} for "#{path}" "#{method.downcase}"))
      end

      # validate request body
      if body.nil? || body == ""
        if meth_spec["requestBody"] && meth_spec["requestBody"]["required"]
          raise RequestValidationError.new(%(Request body required but missed for "#{path}" "#{method.downcase}"))
        end
      else
        body_content_type = content_type.to_s.split(";").first.downcase
        if meth_spec["requestBody"]
          if schema = meth_spec["requestBody"]["content"][body_content_type]
            if body_content_type == "application/json"
              begin
                JSON::Validator.validate!(schema, JSON.load(body))
              rescue => e
                raise RequestValidationError.new("request failed: " + e.message)
              end
            end
          else
            raise RequestValidationError.new(%(Not found request body spec for "#{path}" "#{method.downcase}" "#{body_content_type}"))
          end
        else
          raise RequestValidationError.new(%(Request body provided but not defined in schema for "#{path}" "#{method.downcase}" "#{body_content_type}"))
        end
      end
    end

    def validate_response(method, path, status, content_type, body)
      try_fetch_spec
      raise BrokenSchemaError.new(@schema_error) if @schema_error

      # find path spec
      unless path_spec = find_path(path)
        raise RequestValidationError.new(%(Not found spec for "#{path}"))
      end
      
      # find method spec
      unless meth_spec = path_spec["path"][method.downcase]
        raise RequestValidationError.new(%(Not found spec for "#{path}" "#{method.downcase}"))
      end

      # find status spec
      unless status_spec = (meth_spec["responses"][status.to_s] || meth_spec["responses"]["default"])
        raise NotFoundSpecForStatusError.new(%(Not found spec for "#{path}" "#{method.downcase}" "#{status}"))
      end
      
      if body.nil? || body == ''
        # do nothing
      else
        # find content spec
        resp_content_type = content_type.to_s.split(";").first.downcase
        unless schema = (status_spec["content"] || {})[resp_content_type]
          raise RequestValidationError.new(%(Not found spec for "#{path}" "#{method.downcase}" "#{status}" "#{resp_content_type}"))
        end

        # validate response
        if resp_content_type == "application/json"
          begin
            JSON::Validator.validate!(schema, JSON.load(body))
          rescue => e
            raise RequestValidationError.new(%(schema failed for "#{path}" "#{method.downcase}" "#{status}" "#{resp_content_type}": ) + e.message)
          end
        end
      end
    end

    private

    # Try to get spec every second in case of error
    def try_fetch_spec
      if @next_try.nil? || (@schema_error && Time.now > @next_try)
        puts "[#{Time.now}] Try to fetch spec from #{@target}"
        if @target =~ /^http/
          @spec = JSON.load(open(@target).read)
        elsif [".json"].index(File.extname(@target))
          @spec = JSON.load(File.read(@target))
        elsif [".yml", ".yaml"].index(File.extname(@target))
          @spec = YAML.load(File.read(@target))
        else
          raise "dont know how to open target #{@target}"
        end
        @schema = Parser.new(@spec).to_schema!
        @schema_error = nil
        @next_try = "never"
      end
    rescue => e
      @schema_error = e.message
      @next_try = Time.now + 1
    end

    def find_path(path)
      q = path.split("/").reject { |s| s == "" }
      @schema["paths"].find do |spec|
        q.length == spec["query"].length && spec["query"].zip(q).all? { |want, value|
          (want["kind"] == "const" && want["value"].downcase == value.downcase) ||
          (want["kind"] == "variable")
        }
      end
    end

    def extract_path_params(path, spec)
      q = path.split("/").reject { |s| s == "" }
      spec["query"].zip(q).select { |seg_spec, seg|
        seg_spec["kind"] == "variable"
      }.map { |seg_spec, seg|
        [seg_spec["name"], seg]
      }.to_h
    end
  end
end
