require 'pp'
require 'stringio'
require "socket"
require 'thread'
require 'ruby-debug-base'
if RUBY_VERSION < "1.9"
  require 'ruby-debug/xml_printer'
  require 'ruby-debug/processor'
  require 'ruby-debug/event_processor'
else
  require_relative 'ruby-debug/xml_printer'
  require_relative 'ruby-debug/processor'
  require_relative 'ruby-debug/event_processor'
end

module Debugger
  
  class << self
    # Prints to the stderr using printf(*args) if debug logging flag (-d) is on.
    def print_debug(*args)
      if Debugger.cli_debug
        $stderr.printf(*args)
        $stderr.printf("\n")
        $stderr.flush
      end
    end
    
    def without_stderr
      begin
        if RUBY_PLATFORM =~ /(win32|mingw32)/
          $stderr = File.open('NUL', 'w')
        else
          $stderr = File.open('/dev/null', 'w')
        end
        yield
      ensure
        $stderr = STDERR
      end
    end
    
  end

  class Context
    def interrupt
      self.stop_next = 1
    end
    
    private
    
    def event_processor
      Debugger.event_processor
    end
    
    def at_breakpoint(breakpoint)
      event_processor.at_breakpoint(self, breakpoint)
    end
    
    def at_catchpoint(excpt)
      event_processor.at_catchpoint(self, excpt)
    end
    
    def at_tracing(file, line)
      if event_processor
        event_processor.at_tracing(self, file, line)
      else
        Debugger::print_debug "trace: location=\"%s:%s\", threadId=%d", file, line, self.thnum
      end
    end
    
    def at_line(file, line)
      event_processor.at_line(self, file, line)
    end
 
    def at_return(file, line)
      event_processor.at_return(self, file, line)
    end
  end
  
  class << self
    
    attr_accessor :event_processor, :cli_debug, :xml_debug
    attr_reader :control_thread
    
    #
    # Interrupts the current thread
    #
    def interrupt
      current_context.interrupt
    end
    
    #
    # Interrupts the last debugged thread
    #
    def interrupt_last
      skip do
        if context = last_context
          return nil unless context.thread.alive?
          context.interrupt
        end
        context
      end
    end

    def start_server(host = nil, port = 1234)
      start
      start_control(host, port)
    end

    def debug_program(options)
      start_server(options.host, options.port)

      raise "Control thread did not start (#{@control_thread}}" unless @control_thread && @control_thread.alive?
      
      @mutex = Mutex.new
      @proceed = ConditionVariable.new
      
      # wait for 'start' command
      @mutex.synchronize do
        @proceed.wait(@mutex)
      end
      
      abs_prog_script = File.absolute_path(Debugger::PROG_SCRIPT)
      bt = debug_load(abs_prog_script, options.stop, options.load_mode)
      if bt
        $stderr.print bt.backtrace.map{|l| "\t#{l}"}.join("\n"), "\n"
        $stderr.print "Uncaught exception: #{bt}\n"
      end
    end
    
    def run_prog_script
      return unless @mutex
      @mutex.synchronize do
        @proceed.signal
      end
    end
    
    def start_control(host, port)
      return if @control_thread
      @control_thread = DebugThread.new do
        begin
          $stderr.printf "Fast Debugger (ruby-debug-ide 0.4.9) listens on #{host}:#{port}\n"
          # 127.0.0.1 seemingly works with all systems and with IPv6 as well.
          # "localhost" and nil on have problems on some systems.
          host ||= '127.0.0.1'
          server = TCPServer.new(host, port)
          while (session = server.accept)
            begin
              interface = RemoteInterface.new(session)
              @event_processor = EventProcessor.new(interface)
              ControlCommandProcessor.new(interface).process_commands
            rescue StandardError, ScriptError => ex
              $stderr.printf "Exception in DebugThread loop: #{ex}\n"
              exit 1
            end
          end
        rescue
          $stderr.printf "Exception in DebugThread: #$!\n"
          exit 2
        end
      end
    end
    
  end
  
  class Exception # :nodoc:
    attr_reader :__debug_file, :__debug_line, :__debug_binding, :__debug_context
  end
  
  module Kernel
    #
    # Stops the current thread after a number of _steps_ made.
    #
    def debugger(steps = 1)
      Debugger.current_context.stop_next = steps
    end
    
    #
    # Returns a binding of n-th call frame
    #
    def binding_n(n = 0)
      Debugger.current_context.frame_binding[n+1]
    end
  end
  
end
