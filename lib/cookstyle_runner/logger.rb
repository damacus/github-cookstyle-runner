# typed: true
# frozen_string_literal: true

require 'logger'
require 'json'

module CookstyleRunner
  # Enhanced logger with JSON formatting and component filtering
  class Logger < ::Logger
    # @param logdev [String, IO] Log device (file path or IO object)
    # @param level [Integer] Log level (Logger::DEBUG, Logger::INFO, etc.)
    # @param format [Symbol] Log format (:text or :json)
    # @param components [Array<String>] List of components to enable debug logging for
    def initialize(logdev, level: ::Logger::INFO, format: :text, components: nil)
      @log_format = format
      @debug_components = components&.map(&:to_s) || []
      @context = {}

      super(logdev, level: level)

      # Set up formatter based on format type
      self.formatter = create_formatter
    end

    # Add context that will be included in all subsequent log messages within the block
    # @param context_hash [Hash] Context to add to log messages
    def with_context(context_hash)
      old_context = @context.dup
      @context.merge!(context_hash)
      yield
    ensure
      @context = old_context
    end

    # Override add method to support component filtering and context
    def add(severity, message = nil, progname = nil, **metadata)
      # Extract component from metadata
      component = metadata.delete(:component)

      # Filter debug messages based on component
      return true if severity == DEBUG && !@debug_components.empty? && !component.nil? && !@debug_components.include?(component.to_s)

      # Merge context and metadata
      full_metadata = @context.merge(metadata)
      full_metadata[:component] = component if component

      # Store metadata for formatter to access
      @current_metadata = full_metadata

      # Call parent add
      super(severity, message, progname)
    ensure
      @current_metadata = nil
    end

    # Convenience methods that support metadata
    def debug(message = nil, **metadata)
      add(DEBUG, message, nil, **metadata)
    end

    def info(message = nil, **metadata)
      add(INFO, message, nil, **metadata)
    end

    def warn(message = nil, **metadata)
      add(WARN, message, nil, **metadata)
    end

    def error(message = nil, **metadata)
      add(ERROR, message, nil, **metadata)
    end

    def fatal(message = nil, **metadata)
      add(FATAL, message, nil, **metadata)
    end

    private

    # Create formatter based on format type
    def create_formatter
      case @log_format
      when :json
        json_formatter
      else
        text_formatter
      end
    end

    # JSON formatter
    def json_formatter
      proc do |severity, datetime, _progname, msg|
        log_entry = {
          timestamp: datetime.iso8601,
          level: severity,
          message: msg.to_s
        }
        log_entry.merge!(@current_metadata) if @current_metadata && !@current_metadata.empty?
        "#{JSON.generate(log_entry)}\n"
      end
    end

    # Text formatter
    def text_formatter
      proc do |severity, datetime, _progname, msg|
        timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S')
        base = "[#{timestamp}] #{severity.ljust(5)} -- #{msg}"

        if @current_metadata && !@current_metadata.empty?
          metadata_str = @current_metadata.map { |k, v| "#{k}=#{v}" }.join(' ')
          "#{base} (#{metadata_str})\n"
        else
          "#{base}\n"
        end
      end
    end
  end
end
