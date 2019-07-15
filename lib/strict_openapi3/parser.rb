module StrictOpenapi3
  class Parser
    PATH_NAME_RE = /^(\/(\{?[a-zA-Z0-9_]+\}?)?)+$/
    VERBS = ["get", "post", "patch", "put", "delete"]
    PATH_PARAM_SCHEMAS = [
      {"type" => "string"},
      {"type" => "integer"},
    ]
    QUERY_PARAM_SCHEMAS = [
      {"type" => "string"},
      {"type" => "integer"},
      {"type" => "boolean"},
    ]

    def initialize(json)
      @json = json
    end

    def to_schema!
      parse(@json)
    end

    private

    def parse(json)
      assert_keys("/", json, ["openapi", "info", "paths"], ["components", "tags"])
      out = {}
      parse_openapi(json["openapi"])
      parse_info(json["info"])
      parse_tags(json["tags"] || [])
      if json["components"]
        components = parse_components(json["components"])
      end
      out["paths"] = parse_paths(json["paths"], components, (json["tags"] || []).map { |t| t["name"] })
      out
    end

    def parse_openapi(value)
      assert_equal("/openapi", value, "3.0.0")
    end

    def parse_info(value)
      assert_keys("/info", value, ["version", "title"], ["description"])
    end

    def parse_tags(value)
      value.each_with_index do |tag, index|
        assert_keys("/tags[#{index}]", tag, ["name", "description"], [])
      end
    end

    def parse_paths(value, components, tags)
      paths = value.map do |name, path|
        assert_match("/paths:#{name}", name, PATH_NAME_RE)
        query = name[1..-1].split("/").map { |segment|
          if segment[0..0] == "{"
            {"kind" => "variable", "name" => segment[1..-2]}
          else
            {"kind" => "const", "value" => segment}
          end
        }
        {
          "orig" => name,
          "query" => query,
          "path" => parse_path("/paths:#{name}", path, components, query.select { |q| q["kind"] == "variable" }.map { |q| q["name"] }, tags)
        }
      end
      max_query_length = paths.map { |path| path["query"].length }.max.to_i
      paths.sort_by { |path|
        key = []
        max_query_length.times do |i|
          if path["query"][i].nil?
            key << 0
            key << "empty"
          elsif path["query"][i]["kind"] == "const"
            key << 1
            key << path["query"][i]["value"]
          elsif path["query"][i]["kind"] == "variable"
            key << 2
            key << path["query"][i]["name"]
          else
            raise "unreacheable point"
          end
        end
        key
      }
    end

    def parse_components(value)
      assert_keys("/components", value, ["schemas"], [])
      value["schemas"].map { |name, schema|
        [name, parse_schema("/components:#{name}", schema, {})]
      }.to_h
    end

    def parse_schema(prefix, value, components)
      unless value.is_a?(Hash)
        raise ParseError.new(%(Broken schema: "#{prefix}" should be hash)) 
      end
      assert_keys(prefix, value, [], ["type", "items", "required", "properties", "enum", "additionalProperties", "nullable", "pattern", "minLength", "$ref", "oneOf"])
      if !value.key?("type") && value.key?("$ref")
        assert_keys(prefix + "[no type]", value, [], ["$ref"])
        unless value["$ref"].index("#/components/schemas/") == 0
          raise ParseError.new(%(Broken schema: "#{prefix}:$ref" should have form "#/components/schemas/ComponentName"))
        end
        component_name = value["$ref"].sub("#/components/schemas/", "")
        if components.key?(component_name)
          JSON.load(JSON.dump(components[component_name]))
        else
          raise ParseError.new(%(Broken schema: "#{prefix}:$ref" unknown component "#{component_name}"))
        end
      elsif !value.key?("type") && value.key?("oneOf")
        assert_keys(prefix + "[no type]", value, [], ["oneOf"])
        {"oneOf" => value["oneOf"].each_with_index.map { |branch, i|
          parse_schema("#{prefix}:oneOf[#{i}]", branch, components)
        }}
      elsif value["type"] == "object"
        assert_keys(prefix + "[#{value["type"]}]", value, ["type", "properties"], ["required", "additionalProperties", "nullable"])
        out = {"type" => value["type"]}
        if value["required"]
          unless value["required"].is_a?(Array)
            raise ParseError.new(%(Broken schema: "#{prefix}:required" should be array)) 
          end
          if (value["required"] - value["properties"].keys).length > 0
            raise ParseError.new(%(Broken schema: "#{prefix}" "#{(value["required"] - value["properties"].keys).inspect}" are required but not descipted in properties section))
          end
          out["required"] = value["required"]
        end
        if value.key?("additionalProperties")
          if value["additionalProperties"] == true || value["additionalProperties"] == false
            out["additionalProperties"] = value["additionalProperties"]
          else
            out["additionalProperties"] = parse_schema("#{prefix}:additionalProperties", value["additionalProperties"], components)
          end
        else
          out["additionalProperties"] = false
        end
        out["properties"] = value["properties"].map do |prop, prop_spec|
          [prop, parse_schema("#{prefix}:#{prop}", prop_spec, components)]
        end.to_h
        if value["nullable"]
          {"oneOf" => [out, {"type" => "null"}]}
        else
          out
        end
      elsif value["type"] == "array"
        assert_keys(prefix + "[#{value["type"]}]", value, ["type", "items"], [])
        {
          "type" => "array",
          "items" => parse_schema("#{prefix}:items", value["items"], components)
        }
      elsif value["type"] == "string"
        assert_keys(prefix + "[#{value["type"]}]", value, ["type"], ["nullable", "pattern", "enum", "minLength"])
        if value.key?("enum")
          if value["enum"].is_a?(Array) && value["enum"].all? { |i| i.is_a?(String) }
            # its ok
          else
            raise ParseError.new(%(Broken schema: "#{prefix}:enum" should be array of strings")) 
          end
        end
        if value["nullable"]
          (value.keys - ["nullable"]).map { |k| 
            [k, value[k]]
          }.to_h.merge("type" => [value["type"], "null"])
        else
          value
        end
      elsif value["type"] == "integer" || value["type"] == "boolean" || value["type"] == "float"
        assert_keys(prefix + "[#{value["type"]}]", value, ["type"], ["nullable", "enum"])
        if value["nullable"]
          (value.keys - ["nullable"]).map { |k| 
            [k, value[k]]
          }.to_h.merge("type" => [value["type"], "null"])
        else
          value
        end
      else
        if value["type"]
          raise ParseError.new(%(Broken schema: "#{prefix}" unknown type "#{value["type"]}"))
        else
          raise ParseError.new(%(Broken schema: "#{prefix}" missed type))
        end
      end
    end

    def parse_path(prefix, value, components, path_params, tags)
      value.map do |name, method|
        assert_one_of(prefix, name, VERBS)
        assert_keys("#{prefix}:#{name}", method, ["responses", "summary", "tags"], ["description", "requestBody", "parameters"])
        assert_string_or_nil("#{prefix}:#{name}:description", method["description"])
        assert_string_or_nil("#{prefix}:#{name}:summary", method["summary"])
        unless method["tags"].is_a?(Array) && method["tags"].length == 1
          raise ParseError.new(%(Broken schema: "#{prefix}:#{name}:tags" should be array with one element))
        end
        unless tags.index(method["tags"][0])
          raise ParseError.new(%(Broken schema: "#{prefix}:#{name}:tags[#{method["tags"][0]}]" is not descripted in "tags" section of schema))
        end
        out = {}
        out["parameters"] = (method["parameters"] || []).each_with_index.map { |param, i|
          parse_param("#{prefix}:#{name}:parameters[#{i}]", param)
        }
        known_path_params = out["parameters"].select { |param| param["in"] == "path" }.map { |param| param["name"] }
        if (path_params - known_path_params).length > 0
          raise ParseError.new(%(Broken schema: "#{prefix}:#{name}:parameters" missed path params #{(path_params - known_path_params).inspect}))
        end
        if (known_path_params - path_params).length > 0
          raise ParseError.new(%(Broken schema: "#{prefix}:#{name}:parameters" unknown path params #{(known_path_params - path_params).inspect}))
        end
        if method.key?("requestBody")
          out["requestBody"] = parseRequestBody("#{prefix}:#{name}:requestBody", method["requestBody"], components)
        end
        out["responses"] = method["responses"].map { |code, response|
          assert_one_of("#{prefix}:#{name}:responses:#{code}", code.to_s, ["200", "201", "301", "302", "404", "409", "422", "default"])
          [code.to_s, parse_response("#{prefix}:#{name}:responses:#{code}", response, components)]
        }.to_h
        [name, out]
      end.to_h
    end

    def parse_response(prefix, response, components)
      assert_keys(prefix, response, ["description"], ["content"])
      out = {}
      if response.key?("content")
        out["content"] = response["content"].map { |content_type, content|
          assert_one_of("#{prefix}:#{content_type}", content_type, ["application/json", "text/plain"])
          if content_type == "application/json"
            assert_keys("#{prefix}:#{content_type}", content, ["schema"], [])
            [content_type, parse_schema("#{prefix}:#{content_type}:schema", content["schema"], components)]
          elsif content_type == "text/plain"
            assert_keys("#{prefix}:#{content_type}", content, ["example"], [])
            [content_type, {}]
          else
            raise "unreacheable point"
          end
        }.to_h
      end
      out
    end

    def parseRequestBody(prefix, value, components)
      assert_keys(prefix, value, ["content", "description", "required"], [])
      assert_one_of("#{prefix}:required", value["required"], [true, false])
      {
        "required" => value["required"],
        "content" => value["content"].map { |content_type, content|
          assert_one_of("#{prefix}:#{content_type}", content_type, ["application/json"])
          assert_keys("#{prefix}:#{content_type}", content, ["schema"], [])
          [content_type, parse_schema("#{prefix}:#{content_type}:schema", content["schema"], components)]
        }.to_h
      }
    end

    def parse_param(prefix, value)
      assert_keys(prefix, value, ["name", "in", "description", "required", "schema"], [])
      if value["in"] == "path"
        unless value["required"] == true
          raise ParseError.new(%(Broken schema: "#{prefix}:in[path]" required should be true))
        end
        assert_one_of("#{prefix}:in[schema]", value["schema"], PATH_PARAM_SCHEMAS)
      elsif value["in"] == "query"
        assert_one_of("#{prefix}:query[required]", value["required"], [true, false])
        assert_one_of("#{prefix}:query[schema]", value["schema"], QUERY_PARAM_SCHEMAS)
      else
        raise ParseError.new(%(Broken schema: "#{prefix}:in" unknown value "#{value["in"]}", allow to use ["path", "query"]))
      end
      value
    end

    def assert_match(prefix, value, reg)
      unless value =~ reg
        raise ParseError.new(%(Broken schema: "#{prefix}" expect match "#{reg}"))
      end
    end

    def assert_string_or_nil(prefix, value)
      if value.is_a?(String) || value.nil?
        # all ok
      else
        raise ParseError.new(%(Broken schema: "#{prefix}" expect nil or string, but "#{value}"))
      end
    end

    def assert_one_of(prefix, value, allowed = [])
      unless allowed.index(value)
        raise ParseError.new(%(Broken schema: "#{prefix}" unknown "#{value}", allow to use #{allowed.inspect})) 
      end
    end

    def assert_equal(prefix, value, expected)
      if value != expected
        raise ParseError.new(%(Broken schema: "#{prefix}" expect "#{expected}" but get "#{value}"))
      end
    end

    def assert_keys(prefix, hash, required = [], optional = [])
      if (required - hash.keys).length > 0
        raise ParseError.new(%(Broken schema: "#{prefix}" missed required keys #{(required - hash.keys).inspect}))
      end
      if (hash.keys - required - optional).length > 0
        raise ParseError.new(%(Broken schema: "#{prefix}" unknown keys #{(hash.keys - required - optional).inspect}))
      end
    end
  end
end
