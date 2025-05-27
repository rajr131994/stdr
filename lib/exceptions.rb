  class Exceptions
  end
  class AuthenticationError < StandardError;
  end
  class InvalidTokenError < AuthenticationError;
  end
  class UnavailableError < StandardError;
  end
  class InvalidScopeError < AuthenticationError;
  end
  class TokenInstanceMismatchError < AuthenticationError;
  end
  class ImplementationError < StandardError;
  end

  class ExtractorError < StandardError;
  end
  