class JPEG
    class BTree
        attr_accessor :root

        def initialize(frequencies, values)
            @root = Node.new

            frequencies.each do |freq_count|
                row_values = values.shift(freq_count)
                row_values.each do |i|
                    insert(i)
                end
                extend_tree()
            end
        end

        def to_h
            @root.build_hash("")
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
            return here
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
       
        # adds a value to the true in the left most free position
        # NOTE: if there are no free positions we throw an exception
        #       this method will not insert to complete trees
        def insert(value)
            node = @root.free_node()
            raise "no more free nodes" unless node
            if node.left.nil?
                node.left = value
            elsif node.right.nil?
                node.right = value
            else
                raise "freenode returned non freenode"
            end
        end
        alias :<< :insert

        def extend_tree
            @root.extend_tree()
        end

#        def init_row(row, values)
#            raise "Too many values for row" if values.length > 2**row
#
#            # Fill values left to right
#            values.each_with_index do |v, i|
#                #FIXME
#                node_index = "%0#{row}b" % i # We want a binary string of row length i.e. for row 3 "000", "001", "010"
#                puts node_index
#                self[node_index] = v
#            end
#        end

        class Node
            attr_reader :left
            attr_reader :right
            attr_reader :value

#            def left=(node)
#                #raise "Node already has a value" if @value
#                #raise "Not a node unless" unless node.is_a?(self.class)
#                @left = node
#            end
#
#            def right=(node)
#                #raise "Node already has a value" if @value
#                #raise "Not a node unless" unless node.is_a?(self.class)
#                @right = node
#            end
#
#            def value=(v)
#                #raise "Node already has children" if @left or @right
#                @value = v
#            end

            def to_h
                return {
                    "0" => @left.is_a?(self.class) ? @left.to_h : @left,
                    "1" => @right.is_a?(self.class) ? @right.to_h : @right
                }
            end

            def build_hash(prefix)
                h = Hash.new

                [@left, @right].each_with_index do |side, path|
                    if side.is_a?(self.class)
                        h.merge!(side.build_hash(prefix + path.to_s))
                    else
                        h[prefix + path.to_s] = side
                    end
                end
                return h
            end

            def leaf?
                return @left.nil? && @right.nil?
            end

            def free_node
                return self if @left.nil? || @right.nil?

                [@left, @right].each do |side|
                    if @left.is_a?(self.class)
                        next_free_node = side.free_node
                        return next_free_node if next_free_node
                    end
                end
                return false
            end

            def extend_tree
                if @left.nil?
                    @left = Node.new
                elsif @left.is_a?(self.class)
                    @left.extend_tree()
                else
                    #its data
                end

                if @right.nil?
                    @right = Node.new
                elsif @right.is_a?(self.class)
                    @right.extend_tree()
                else
                    #its data
                end
            end

            def each_node(&b)
                if @left.is_a?(self.class)
                    @left.each_node(&b)
                else
                    b.call(@left)
                end
                if @right.is_a?(self.class)
                    @right.each_node(&b)
                else
                    b.call(@right)
                end
            end

            def depth
                return [@left.is_a?(self.class) ? @left.depth : 0, @right.is_a?(self.class) ? @right.depth : 0].max + 1
            end
        end
    end
end
