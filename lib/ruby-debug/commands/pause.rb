module Debugger

  # Implements debugger "pause" command
  class PauseCommand < Command
    self.allow_in_control = true

    def regexp
      /^\s*pause\s*$/
    end

    def execute
      if RUBY_VERSION < "1.9"
        print_msg "Not implemented"
        return
      end
      @state.context.pause
    end

    class << self
      def help_command
        %w[jump]
      end

      def help(cmd)
        %{
          pause\tpause a running thread
         }
     end
    end
  end
end
