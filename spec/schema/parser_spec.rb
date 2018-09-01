describe StrictOpenapi3::Parser do
  it "failed on missed required key" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "paths" => {},
      }).to_schema!
    end.to raise_error('Broken schema: "/" missed required keys ["info"]')
  end

  it "failed on unknown key" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "info" => {},
        "paths" => {},
        "unknown_key" => "yo"
      }).to_schema!
    end.to raise_error('Broken schema: "/" unknown keys ["unknown_key"]')
  end

  it "failed on wrong openapi" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "2.0.0",
        "info" => {},
        "paths" => {},
      }).to_schema!
    end.to raise_error('Broken schema: "/openapi" expect "3.0.0" but get "2.0.0"')
  end

  describe "wrong component" do
    it "missed properties for object" do
      expect do
        StrictOpenapi3::Parser.new({
          "openapi" => "3.0.0",
          "info" => {"version" => "0.0.0", "title" => "test schema"},
          "components" => {"schemas" => {"Some" => {"type" => "object"}}},
          "paths" => {},
        }).to_schema!
      end.to raise_error('Broken schema: "/components:Some[object]" missed required keys ["properties"]')
    end

    it "unknown attribute for object" do
      expect do
        StrictOpenapi3::Parser.new({
          "openapi" => "3.0.0",
          "info" => {"version" => "0.0.0", "title" => "test schema"},
          "components" => {"schemas" => {"Some" => {"type" => "object", "properties" => {}, "unknown_attribute" => {}}}},
          "paths" => {},
        }).to_schema!
      end.to raise_error('Broken schema: "/components:Some" unknown keys ["unknown_attribute"]')
    end

    it "broken required for object" do
      expect do
        StrictOpenapi3::Parser.new({
          "openapi" => "3.0.0",
          "info" => {"version" => "0.0.0", "title" => "test schema"},
          "components" => {"schemas" => {"Some" => {"type" => "object", "properties" => {}, "required" => "broken"}}},
          "paths" => {},
        }).to_schema!
      end.to raise_error('Broken schema: "/components:Some:required" should be array')
    end

    it "unknown required for object" do
      expect do
        StrictOpenapi3::Parser.new({
          "openapi" => "3.0.0",
          "info" => {"version" => "0.0.0", "title" => "test schema"},
          "components" => {"schemas" => {"Some" => {"type" => "object", "properties" => {}, "required" => ["some"]}}},
          "paths" => {},
        }).to_schema!
      end.to raise_error('Broken schema: "/components:Some" "["some"]" are required but not descipted in properties section')
    end
  end

  it "failed on wrong path name" do
    [
      "this-is-not-valid-path",
      "/ xxx",
      "/{{abc}}",
      "/{ab}a",
    ].each do |path|
      expect do
        StrictOpenapi3::Parser.new({
          "openapi" => "3.0.0",
          "info" => {"version" => "0.0.0", "title" => "test schema"},
          "paths" => {path => {}},
        }).to_schema!
      end.to raise_error(%(Broken schema: "/paths:#{path}" expect match "#{StrictOpenapi3::Parser::PATH_NAME_RE}"))
    end
  end

  it "failed on wrong verb" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "info" => {"version" => "0.0.0", "title" => "test schema"},
        "paths" => {"/" => {"doit" => {}}},
      }).to_schema!
    end.to raise_error(%(Broken schema: "/paths:/" unknown "doit", allow to use #{StrictOpenapi3::Parser::VERBS.inspect}))
  end

  it "failed on missed params parameters" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "info" => {"version" => "0.0.0", "title" => "test schema"},
        "tags" => [{"name" => "tag", "description" => "desc"}],
        "paths" => {"/pets/{id}" => {"get" => {
          "summary" => "get",
          "tags" => ["tag"],
          "responses" => {
            "200" => {}
          }
        }}},
      }).to_schema!
    end.to raise_error(%(Broken schema: "/paths:/pets/{id}:get:parameters" missed path params ["id"]))
  end

  it "failed on unknown path parameters" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "info" => {"version" => "0.0.0", "title" => "test schema"},
        "tags" => [{"name" => "tag", "description" => "desc"}],
        "paths" => {"/pets" => {"get" => {
          "summary" => "get",
          "tags" => ["tag"],
          "parameters" => [
            {"name" => "unk", "in" => "path", "required" => true, "description" => "unk", "schema" => {"type" => "string"}}
          ],
          "responses" => {
            "200" => {"description" => "suc"}
          }
        }}},
      }).to_schema!
    end.to raise_error(%(Broken schema: "/paths:/pets:get:parameters" unknown path params ["unk"]))
  end

  it "pass valid schema" do
    expected = YAML.load(File.read(File.expand_path("../factories/api_compilated.yaml", __dir__)))
    schema = StrictOpenapi3::Parser.new(YAML.load(File.read(File.expand_path("../factories/api.yaml", __dir__)))).to_schema!
    # File.write(File.expand_path("../factories/api_compilated.yaml", __dir__), YAML.dump(schema))
    expect(schema).to eq(expected)
  end

  it "expects summary for each method" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "info" => {"version" => "0.0.0", "title" => "test schema"},
        "paths" => {"/pets" => {"get" => {
          "description" => "get",
          "responses" => {
            "200" => {"description" => "succes"}
          }
        }}}
      }).to_schema!
    end.to raise_error('Broken schema: "/paths:/pets:get" missed required keys ["summary", "tags"]')
  end

  it "expects one tag for each method" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "info" => {"version" => "0.0.0", "title" => "test schema"},
        "paths" => {"/pets" => {"get" => {
          "summary" => "Get pets",
          "tags" => ["tag1", "tag2"],
          "responses" => {
            "200" => {"description" => "succes"}
          }
        }}}
      }).to_schema!
    end.to raise_error('Broken schema: "/paths:/pets:get:tags" should be array with one element')
  end

  it "Each tag should be descripted in head of schema" do
    expect do
      StrictOpenapi3::Parser.new({
        "openapi" => "3.0.0",
        "tags" => [{"name" => "tag1", "description" => "this is tag1"}],
        "info" => {"version" => "0.0.0", "title" => "test schema"},
        "paths" => {"/pets" => {"get" => {
          "summary" => "Get pets",
          "tags" => ["tag2"],
          "responses" => {
            "200" => {"description" => "succes"}
          }
        }}}
      }).to_schema!
    end.to raise_error('Broken schema: "/paths:/pets:get:tags[tag2]" is not descripted in "tags" section of schema')
  end
end
