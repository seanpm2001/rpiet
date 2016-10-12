require_relative 'node'
require_relative 'math_node'

module RPiet
  ##
  # Add two values from stack
  class DivNode < MathNode
    def initialize(step, x, y)
      super(step, x, y, :/)
    end
  end
end