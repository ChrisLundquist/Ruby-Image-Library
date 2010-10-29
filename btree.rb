class JPEG
    class BTree
        attr_accessor :root

        def initialize(frequencies, values)
            values.flatten!

            @root = Node.new

            frequencies.each_with_index do |freq_count, row|
                puts "row: " + row.to_s
                row_values = values.shift(freq_count)
                puts "values: " + row_values.inspect
                init_row(row, row_values)
            end
        end

        def [](index)
            #index = index.unpack("B*").first unless index =~ /\A[01]+\Z/

            here = @root
            index.each_char do |b|
                case b
                when "0"
                    if here and here.left
                        here = here.left
                    else
                        # The path isn't defined in our tree
                        return nil
                    end
                when "1"
                    if here and here.right
                        here = here.right
                    else
                        # The path isn't defined in our tree
                        return nil
                    end
                else
                    raise ArgumentError.new("'#{index.inspect}' is not a binary string")
                end
            end
            return here.value
        end

        def []=(index, value)
            #index = index.unpack("B*").first unless index =~ /\A[01]+\Z/

            here = @root
            index.each_char do |b|
                case b
                when "0"
                    here.left ||= Node.new # We create connecting nodes only as needed
                    here = here.left
                when "1"
                    here.right ||= Node.new
                    here = here.right
                else
                    raise ArgumentError.new("'#{index.inspect}' is not a binary string")
                end
            end
            return here.value = value
        end

        # Check that every leaf has a value
        def complete?
            self.each do |v|
                return false if v.nil?
            end
            return true
        end

        def depth
            @root.depth
        end

        def each(&b)
            @root.each_node(&b)
        end

        def leaf_count
            count = 0
            @root.each_node do |n|
                count += 1 if n and n.leaf?
            end
            return count
        end
        private

        def init_row(row, values)
            raise "Too many values for row" if values.length > 2**row

            # Fill values left to right
            values.each_with_index do |v, i|
                #FIXME
                node_index = "%0#{row}b" % i # We want a binary string of row length i.e. for row 3 "000", "001", "010"
                puts node_index
                self[node_index] = v
            end
        end


        class Node
            attr_reader :left
            attr_reader :right
            attr_reader :value

            def left=(node)
                #raise "Node already has a value" if @value
                #raise "Not a node unless" unless node.is_a?(self.class)
                @left = node
            end

            def right=(node)
                #raise "Node already has a value" if @value
                #raise "Not a node unless" unless node.is_a?(self.class)
                @right = node
            end

            def value=(v)
                #raise "Node already has children" if @left or @right
                @value = v
            end

            def leaf?
                return @left.nil? && @right.nil?
            end

            def each_node(&b)
                if @value
                    b.call(self)
                end
                if @left
                    @left.each_node(&b)
                else
                    b.call(nil) # Since we create nodes lazily, the value, left and right may all be nil
                end

                if @right
                    @right.each_node(&b)
                else
                    b.call(nil)
                end
            end

            def each(&b)
                each_node do |node|
                    b.call(node.value)
                end
            end

            def depth
                return [@left ? @left.depth : 0, @right ? @right.depth : 0].max + 1
            end
        end
    end
end
