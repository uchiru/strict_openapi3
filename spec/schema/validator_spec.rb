describe StrictOpenapi3::Validator do
  let (:validator) { StrictOpenapi3::Validator.new(File.expand_path("../factories/api.yaml", __dir__)) }

  it "json-schema test" do
    expect do
      JSON::Validator.validate!({
        "type" => "object",
        "required" => ["cmd"],
        "properties" => {
          "cmd" => {"type" => ["string", "null"]}
        }
      }, {"cmd" => nil})
    end.to_not raise_error
  end

  it "json-schema test - 2" do
    expect do
      JSON::Validator.validate!({
        "type" => "object",
        "required" => ["cmd"],
        "properties" => {
          "cmd" => {"type" => ["string", "null"]}
        }
      }, {"cmd" => "cmd"})
    end.to_not raise_error
  end

  describe 'request' do
    it "fails on broken schema" do
      broken = StrictOpenapi3::Validator.new(File.expand_path("../factories/broken.yaml", __dir__))
      expect do
        broken.validate_request("GET", "/stats", {}, "application/json; charset=utf-8", '')
      end.to raise_error(StrictOpenapi3::BrokenSchemaError)
    end

    it 'fails unknown path' do
      expect do
        validator.validate_request("POST", "/unknown", {}, "application/json; charset=utf-8", '')
      end.to raise_error(%(Not found spec for "/unknown"))
    end

    it 'fails unknown verb' do
      expect do
        validator.validate_request("TEAPOT", "/pets", {}, "application/json; charset=utf-8", '')
      end.to raise_error(%(Not found spec for "/pets" "teapot"))
    end

    it 'fails unknown content type' do
      expect do
        expect(validator.validate_request("POST", "/pets", {}, "application/xml", '<pet />'))
      end.to raise_error(%(Not found request body spec for "/pets" "post" "application/xml"))
    end

    it 'fails missed body' do
      expect do
        expect(validator.validate_request("POST", "/pets", {}, "application/json", ''))
      end.to raise_error(%(Request body required but missed for "/pets" "post"))
    end

    it 'fails unrequired body' do
      expect do
        expect(validator.validate_request("GET", "/pets", {"extend" => true}, "application/json", '<body/>'))
      end.to raise_error(%(Request body provided but not defined in schema for "/pets" "get" "application/json"))
    end

    it 'fails broken request schema' do
      expect do
        expect(validator.validate_request("POST", "/pets", {}, "application/json", '{"pet":{}}'))
      end.to raise_error(%(request failed: The property '#/pet' did not contain a required property of 'name'))
    end

    it 'fails broken request schema-2' do
      expect do
        expect(validator.validate_request("POST", "/pets", {}, "application/json", '{"pet":{"name":"bot","age":62}}'))
      end.to raise_error(%(request failed: The property '#/pet' contains additional properties ["age"] outside of the schema when none are allowed))
    end

    it 'fails broken path params' do
      expect do
        expect(validator.validate_request("GET", "/pets/pet", {}, "application/json", ''))
      end.to raise_error(%(Expect integer param "id" but get "pet" for "/pets/pet" "get"))
    end

    it 'passes correct path params' do
      expect do
        expect(validator.validate_request("GET", "/pets/123", {}, "application/json", ''))
      end.to_not raise_error
    end

    it 'fails on missed query param' do
      expect do
        expect(validator.validate_request("GET", "/pets", {}, "application/json", ''))
      end.to raise_error(%(Missed required params ["extend"] for "/pets" "get"))
    end

    it 'fails on broken query param' do
      expect do
        expect(validator.validate_request("GET", "/pets", {"extend" => "abc"}, "application/json", ''))
      end.to raise_error(%(Expect boolean param "extend" but get "abc" for "/pets" "get"))
    end

    it 'fails on unknown query param' do
      expect do
        expect(validator.validate_request("GET", "/pets", {"extend" => true, "some" => 123}, "application/json", ''))
      end.to raise_error(%(Unknown param "some" for "/pets" "get"))
    end

    it 'passes correct query params' do
      expect do
        expect(validator.validate_request("GET", "/pets", {"extend" => false}, "application/json", ''))
      end.to_not raise_error
    end

    it 'passes correct request' do
      expect do
        expect(validator.validate_request("POST", "/pets", {}, "application/json", '{"pet":{"name":"bob"}}'))
      end.to_not raise_error
    end

    it 'passes correct request' do
      expect do
        expect(validator.validate_request("POST", "/pets", {}, "application/json", '{"pet":{"name":"bob"}}'))
      end.to_not raise_error
    end

    it 'failes broken pet name' do
      expect do
        expect(validator.validate_request("POST", "/pets", {}, "application/json", '{"pet":{"name":"0bob"}}'))
      end.to raise_error(%(request failed: The property '#/pet/name' value "0bob" did not match the regex '^[a-z][a-z0-9\\-_]+$'))
    end
  end

  describe 'response' do
    it "fails on broken schema" do
      broken = StrictOpenapi3::Validator.new(File.expand_path("../factories/broken.yaml", __dir__))
      expect do
        broken.validate_response("GET", "/pets", 200, "application/json; charset=utf-8", '{"pets":[]}')
      end.to raise_error(StrictOpenapi3::BrokenSchemaError)
    end

    it 'fails unknown path' do
      expect do
        validator.validate_response("POST", "/unknown", 200, "application/json; charset=utf-8", '')
      end.to raise_error(%(Not found spec for "/unknown"))
    end

    it 'fails unknown verb' do
      expect do
        validator.validate_response("TEAPOT", "/pets", 200, "application/json; charset=utf-8", '')
      end.to raise_error(%(Not found spec for "/pets" "teapot"))
    end

    it 'fails unknown status' do
      expect do
        expect(validator.validate_response("GET", "/pets", 201, "application/json", ''))
      end.to raise_error(%(Not found spec for "/pets" "get" "201"))
    end

    it 'fails unknown content type' do
      expect do
        expect(validator.validate_response("GET", "/pets", 200, "application/xml", '<root/>'))
      end.to raise_error(%(Not found spec for "/pets" "get" "200" "application/xml"))
    end

    it 'fails unknown content type' do
      expect do
        expect(validator.validate_response("GET", "/pets", 200, "application/xml", '<root/>'))
      end.to raise_error(%(Not found spec for "/pets" "get" "200" "application/xml"))
    end

    it 'fails broken body response' do
      expect do
        expect(validator.validate_response("GET", "/pets", 200, "application/json", '{"pets":'))
      end.to raise_error(/schema failed for "\/pets" "get" "200" "application\/json":/)
    end

    it 'fails broken scheman response' do
      expect do
        expect(validator.validate_response("GET", "/pets", 200, "application/json", '{"pets":[{"age":48}]}'))
      end.to raise_error(%(schema failed for "/pets" "get" "200" "application/json": The property '#/pets/0' did not contain a required property of 'id'))
    end

    it 'passes valid response' do
      expect do
        expect(validator.validate_response("GET", "/pets", 200, "application/json", '{"pets":[{"id":123,"name":"bob"}]}'))
      end.to_not raise_error
    end

    it 'passes valid response - 2' do
      expect do
        expect(validator.validate_response("POST", "/pets", 201, "application/json", ''))
      end.to_not raise_error
    end

    it 'passes nullable as null' do
      expect do
        expect(validator.validate_response("GET", "/nullable", 200, "application/json", '{"obj":null}'))
      end.to_not raise_error
    end

    it 'passes nullable as object' do
      expect do
        expect(validator.validate_response("GET", "/nullable", 200, "application/json", '{"obj":{"some":"abc"}}'))
      end.to_not raise_error
    end

    it 'failse nullable as wrong object' do
      expect do
        expect(validator.validate_response("GET", "/nullable", 200, "application/json", '{"obj":{"some":"abc","another":"cde"}}'))
      end.to raise_error(%(schema failed for "/nullable" "get" "200" "application/json": The property '#/obj' of type object did not match any of the required schemas))
    end

    describe 'oneOf' do
      it 'passes #1' do
        expect do
          expect(validator.validate_response("GET", "/one_of", 200, "application/json", '{"image":{"image_type":"image","image_name":"redis"}}'))
        end.to_not raise_error
      end

      it 'passes #2' do
        expect do
          expect(validator.validate_response("GET", "/one_of", 200, "application/json", '{"image":{"image_type":"repo","image_repo":"uchiru/uchiru"}}'))
        end.to_not raise_error
      end

      it 'failed unknown type' do
        expect do
          expect(validator.validate_response("GET", "/one_of", 200, "application/json", '{"image":{"image_type":"some","image_repo":"uchiru/uchiru"}}'))
        end.to raise_error(%(schema failed for "/one_of" "get" "200" "application/json": The property '#/image' of type object did not match any of the required schemas))
      end

      it 'failed broken obj' do
        expect do
          expect(validator.validate_response("GET", "/one_of", 200, "application/json", '{"image":{"image_type":"image","image_repo":"uchiru/uchiru"}}'))
        end.to raise_error(%(schema failed for "/one_of" "get" "200" "application/json": The property '#/image' of type object did not match any of the required schemas))
      end
    end
  end
end
