module StrictOpenapi3
  class Error < RuntimeError; end
  class ParseError < Error; end
  class BrokenSchemaError < Error; end
  class RequestValidationError < Error; end
  class NotFoundSpecForStatusError < Error; end
end
