module Debugger

  # Implements debugger "pause" command
  class PauseCommand < Command
    self.control = true

    def regexp
      /^\s*pause\s*(?:\s+(\S+))?\s*$/
    end

    def execute
      if RUBY_VERSION < "1.9"
        print_msg "Not implemented"
        return
      end
      c = get_context(@match[1].to_i)
      c.pause
    end

    class << self
      def help_command
        %w[pause]
      end

      def help(cmd)
        %{
          pause <nnn>\tpause a running thread
         }
     end
    end
  end
end
