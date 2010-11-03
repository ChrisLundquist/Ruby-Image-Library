class JPEG
    require 'matrix'
    FILE_MAGIC_NUMBER = [0xFF,0xD8]    # To validate we are opening a JPEG file
    START_OF_IMAGE = 0xD8              # File magic Number
    START_OF_FRAME = 0xC0              # baseline DCT
    PROGRESSIVE_START_OF_FRAME = 0xC2  # Progressive DCT
    DEFINE_HUFFMAN_TABLES = 0xC4       # Specifies one or more Huffman tables
    DEFINE_QUANTIZATION_TABLES = 0xDB  # Specified one or more quantization tables
    DEFINE_RESTART_INTERVAL = 0xDD     # Specifies the interval between RST n markers in macroblocks.
    START_OF_SCAN = 0xDA               #
    RESTART = 0xD7                     # Inserted every r macroblocks where r is the restart interval set by a DRI marker
    APPLICATION_SPECIFIC = 0xE0..0xEF  # Anything the application wants to save in this
    COMMENT = 0xFE                     # Contains a text comment
    END_OF_IMAGE = 0xD9                #

    ZRL = 0xF0                         # Indicates a run of 16 zeros
    END_OF_BLOCK = 0x00                # Indicates the end of a mcu component

    # Maps a component id to the component symbol
    COMPONENT_ID_TO_SYMBOL = {1=> :y, 2=> :cb, 3=> :cr, 4 =>:i, 5 =>:q }
    # Maps a color space id to the color space symbol
    COLOR_SPACE_ID_TO_SYMBOL = { 1 => :grey, 3 => :ycbcr, 4 => :cmyk}

    COEFFECIENTS = { :red => 0.299, :green => 0.587, :blue => 0.114 }

    attr_reader \
        :start_of_frame,        # Data in the start_of_frame marker
        :huffman_tables,        # Data from the define huffman tables marker
        :quantization_tables,   # Data from quantization tables marker
        :restart_interval,
        :start_of_scan,         # Data in the start_of_scan marker
        :image,                 # Data describing our image
        :restart,
        :appication_specific,
        :comment,
        :file,          # The File (handle) to our object
        :file_path,     # The string file path of our image
        :height,        # height of the image
        :width,         # width of the image
        :color_space    # 

    def initialize(file)
        # Initialize our variables here so we don't have to check if they are later
        @huffman_tables = Array.new
        @quantization_tables = Array.new
        @application_specific = Array.new
        @comment = Array.new
        @last_dc_value = Hash.new(0)
        case file
        when File
            @file = file
            @file_path = file.path
            new_from_file()
        when String
            @file_path = file
            new_from_path()
        else
            raise ArgumentError.new("Unable to initialize from " + file.class)
        end
    end

    def inspect
        "#{file_path} #{@height}x#{@width} #{@color_space}"
    end

    def to_ycbcr # FIXME
        # No work to be done
        return unless @color_space == :rgb
        ycbcr_image = Array.new

        @image.each_slice(3) do |r,g,b|
            y = COEFFECIENTS[:red] * r + COEFFECIENTS[:green] * g + COEFFECIENTS[:blue] * b
            cb = (b - y) / ( 2 - 2 * COEFFECIENTS[:blue] )
            cr = (r - y) / ( 2 - 2 * COEFFECIENTS[:red] )
            ycbcr_image += [y.to_i, cb.to_i, cr.to_i]
        end
        @image = ycbcr_image
    end

    def to_rgb
        # No work to be done
        return unless @color_space == :ycbcr
        rgb_image = Array.new
        @image.each_slice(3) do |y, cb, cr|
            red = cr * ( 2 - 2 *COEFFECIENTS[:red] ) + y
            blue = cr * ( 2 - 2 *COEFFECIENTS[:blue] ) + y
            green = (y - COEFFECIENTS[:blue] * blue - COEFFECIENTS[:red] * red) / COEFFECIENTS[:green]

            # We have to shift it by 128 to go from [-127..128] to [0..255]
            rgb_image += [red.to_i + 128, green.to_i + 128, blue.to_i + 128]
        end
        # Update our color space so we don't double convert
        @color_space = :rgb
        @image = rgb_image
    end

    # Converts the instance to a Bitmap object
    def to_bmp
    end

    private 
    def new_from_file
        parse_markers()
        # Tells us our color space and dimensions
        parse_start_of_frame()
        # The quantization tables to use
        parse_quantization_tables()
        # The huffman tables
        parse_huffman_tables()
        # The info on which huffman table to use for each component
        parse_start_of_scan()
        # decodes the entropy encoded data into MCUs
        parse_scan()
        # Turns the decoded DCTs into ycrcb color space
        dct_to_ycrcb()
        # We have 2D arrays of macro blocks that we need to turn into a 1d array of pixels
        macro_blocks_to_pixels()
    end

    def new_from_path
        @file = File.open(@file_path)
        new_from_file()
    end

    # Reads the markers in the jpeg header
    def parse_markers
        while header = @file.read(2)
            marker, type = header.unpack("CC")

            case type
            when START_OF_IMAGE             # 216
                # Do nothing
            when START_OF_FRAME             # 192
                @start_of_frame = read_data_segment()
            when PROGRESSIVE_START_OF_FRAME
                raise "unimplemented marker"
            when DEFINE_HUFFMAN_TABLES      # 196
                @huffman_tables << read_data_segment()
            when DEFINE_QUANTIZATION_TABLES # 219
                @quantization_tables << read_data_segment()
            when DEFINE_RESTART_INTERVAL
                raise "unimplemented marker"
            when START_OF_SCAN
                @start_of_scan = read_entropy_encoded_segment()
            when RESTART
                raise "unimplemented marker"
            when APPLICATION_SPECIFIC  # 224..240
                @application_specific << read_data_segment()
            when COMMENT
                @comment << read_data_segment()
            when END_OF_IMAGE
                # All Done
            else
                raise "unrecognized marker: #{marker} #{type}"
                # We have an unrecognized method, we will try to fetch it's data
                #read_data_segment()
            end
        end
        @file.close
    end

    # Reads the first two bytes after a marker to see how much to read
    # then returns the unpacked data for the segment
    def read_data_segment
        len = @file.read(2).unpack("n").first
        # TODO progressive scan files will have multiple scan segments
        data = @file.read(len - 2) or raise "Could not fetch data segment"
        data = data.unpack("C*")
        return data
    end

    # NOTE this mutates the entropy encoded segment by removing the bit stuffed 0s after 0xFF
    # NOTE: In entropy encoded data to avoid framing errors, a 0xFF will be followed by 0x00
    #       if a 0xFF was intended and not the start of a marker
    def read_entropy_encoded_segment
        data = []

        while byte = @file.getbyte
            if byte == 0xff
                byte = @file.getbyte

                if byte == 0x00
                    byte = 0xff # so we push the 0xff instead of a byte stuffed 0x00
                else
                    # We have another marker for a segment
                    @file.seek(-2,IO::SEEK_CUR) # Back the file up, we found another marker
                    return data
                end
            end
            data << byte
        end
        return data
    end

    # interprets the start of frame marker and sets
    # @width
    # @height
    # @color_space
    # @sample_ratios
    # @data_precision
    def parse_start_of_frame
        # Sample input for @start_of_frame
        # [8, 4, 176, 6, 64, 3, 1, 17, 0, 2, 17, 1, 3, 17, 1]
        @data_precision = @start_of_frame.first # Usually 8

        # These 2 bytes are interpretted together as a short
        @height = (@start_of_frame[1] << 8) + @start_of_frame[2]
        @width = (@start_of_frame[3] << 8) + @start_of_frame[4]

        @color_space = COLOR_SPACE_ID_TO_SYMBOL[@start_of_frame[5]]
        @samples = Hash.new

        # Helper function that unpacks the sample ratio
        # Sampling factors (bit 0-3 vert., 4-7 hor.)
        get_sample_ratio = lambda { |sample_byte| return Rational(sample_byte & 0x0F, sample_byte & 0xF0 >> 4) } 

        @start_of_frame[6..-1].each_slice(3) do |component_id, sample_factors, quantization_table_id|
            @samples[COMPONENT_ID_TO_SYMBOL[component_id]]  = { :ratio => get_sample_ratio.call(sample_factors), :quantization_table_id => quantization_table_id }
        end
    end

    def parse_start_of_scan
        #  - length (high byte, low byte), must be 6+2*(number of components in scan)
        #  - number of components in scan (1 byte), must be >= 1 and <=4 (otherwise error), usually 1 or 3
        #  - for each component: 2 bytes
        #     - component id (1 = Y, 2 = Cb, 3 = Cr, 4 = I, 5 = Q), see SOF0
        #     - Huffman table to use:
        #       - bit 0..3: AC table (0..3)
        #       - bit 4..7: DC table (0..3)
        #  - 3 bytes to be ignored (???)

        # The start of scan segment tells us how to interpret the data. Such as which tables to use for each component
        @scan = @start_of_scan

        # The first two bytes of the segment is the length of this scan
        length_high, length_low = @scan.shift(2)
        length = (length_high << 8) + length_low

        # IMPORTANT length - 2 because the length 2 byte header counts itself
        @start_of_scan = @scan.shift(length - 2)

        number_of_components_to_scan = @start_of_scan.shift()
        raise "Invalid number of components to scan: #{number_of_components_to_scan}" unless (1..4).include?(number_of_components_to_scan)

        scan_table = Hash.new

        # Parse which ac/dc huffman tables to use for each component
        number_of_components_to_scan.times do |component|
            component_id, huffman_table = @start_of_scan.shift(2)
            ac_huffman_table_id = huffman_table & 0x0F
            dc_huffman_table_id = (huffman_table & 0xF0) >> 4
            scan_table[COMPONENT_ID_TO_SYMBOL[component_id]] = { :ac_id => ac_huffman_table_id, :dc_id => dc_huffman_table_id} 
        end
        # The scan table tells us which huffman table to use for each component
        @start_of_scan = scan_table
    end

    def parse_scan
        #TODO OPTIMIZE mapping it to a string is expensive
        @scan = @scan.map { |i| "%08b" % i }.join if @scan.is_a?(Array)
        case @color_space
        when :ycbcr
            parse_ycbcr_scan()
        when :rgb
            raise "not implemented"
        else
            raise "color space parsing of '#{@color_space}' not implimented"
        end
    end

    def parse_ycbcr_scan
        macro_blocks = Array.new
        #OPTIMIZE The end of the file is padded with all 1s so if there are no zeros
        #         we know we can stop
        while @scan.include?("0")
            [:y,:cb,:cr].each do |component|
                macro_blocks << get_mcu_component(component)
            end
        end
        @dct = macro_blocks
    end

    # Returns the 8x8 DCT coeffecient matrix (as a sparse hash) for the given component
    def get_mcu_component(component)
        dc_table = huffman_table_for_component(component,:dc) 
        ac_table = huffman_table_for_component(component,:ac)

        # We will have up to 64 entries representing coeffecients of a DCT
        # Here we will use a hash to simulate a sparse array
        mcu = Hash.new(0)

        # The first value encoded is the DC for the component
        mcu[0] = get_next_scan_value(dc_table)
        index = 1
        while value = get_next_scan_value(ac_table)
            case value
            when END_OF_BLOCK
                break
            when ZRL # 16 zeros
                index += 16
            else
                # We should never have more than 64 components in an mcu
                raise "abnormally long mcu" if index > 64 
                mcu[index] = value
            end
        end
        # Each DC value is stored as a delta from the previous
        mcu[0] += @last_dc_value[component]
        @last_dc_value[component] = mcu[0]
        mcu
    end

    # Reads bits that match our huffman tree's path then reads that many more bits and interprets and returns the value
    def get_next_scan_value(huffman_table)
        # Use the longest code of this table
        huffman_table[:max_key_length].times do |i|
            if length_of_value = huffman_table[@scan[0..i]]
                # Shift of this valid huffman code from our image
                huffman_code = @scan.slice!(0, i + 1)

                value = @scan.slice!(0, length_of_value)
                value = binary_string_to_i(value)
                return value
            end
        end
        raise "No value found a subset of: #{@scan[0..16].inspect}\nHuffman Table:\n #{huffman_table.inspect}"
    end

    # Interprets a signed binary string as a decimal value
    def binary_string_to_i(value)
        if value[0] == 48          # If its a leading zero to_i will throw it away
            value = ~value.to_i(2) # Really its a negative number
        else
            value = value.to_i(2)  # Just a positive number
        end
    end

    # Returns the huffman table to use for +component+, and +type+
    def huffman_table_for_component(component,type)
        type_id = "#{type}_id".to_sym
        @huffman_tables[type][@start_of_scan[component][type_id]] or \
            raise("#{type} #{component} huffman table is nil: 
                  #{@huffman_tables.inspect} 
                  start_of_scan: #{@start_of_scan.inspect}")
    end

    # IMPORTANT NOTE sometimes one DHT marker will have multiple huffman tables inside it
    def parse_huffman_tables
        #  HT information (1 byte):
        #  bit 0..3: number of HT (0..3, otherwise error)
        #  bit 4   : type of HT, 0 = DC table, 1 = AC table
        #  bit 5..7: not used, must be 0
        tables = Hash.new
        tables[:ac] = Hash.new
        tables[:dc] = Hash.new

        # Find the type and ID of each huffman table
        @huffman_tables.each do |table|
            # If they packed multiple huffman tables in one marker
            while table.length > 0
                info_byte = table.shift           # The first byte tells us about the huffman table to follow
                table_id = info_byte & 0x07       # this SHOULD be 0..3 but sometimes adobe does what they want
                ac_table = (info_byte & 0x10) > 0 # this bit says if its an AC table
                table_type = ac_table ? :ac : :dc   # its either AC or DC

                # The first 16 bytes represent the frequency table
                frequencies = table.shift(16)

                # We need to know how many entries the frequency table needs to be satisfied
                table_entries = 0
                frequencies.each do |i|
                    table_entries += i
                end

                raise "Malformed huffman table. Missing data presumed
                entries: #{table_entries} 
                table: #{table.inspect}
                frequencies: #{frequencies.inspect}" if table_entries > table.length

                data = table.shift(table_entries)
                tables[table_type][table_id] = build_huffman_hash(frequencies,data)
                tables[table_type][table_id][:max_key_length] = tables[table_type][table_id].keys.max{|a, b| a.length <=> b.length}.length
            end
        end
        @huffman_tables = tables
        return @hufman_tables
    end

    # Takes the frequency tables and the values from the DHT and returns a hash
    # with keys matching the path and storing the associated value
    # E.G. table["100"] => 3 (right,left,left)
    def build_huffman_hash(frequencies, values)
        table = Hash.new

        # The number of leading entries in each row to skip because they are "blocked" but leaf nodes in previous rows
        blocked_entry_count = 0

        frequencies.each_with_index do |frequency, bit_length|
            # Each_with_index starts at 0, but our frequency table starts at 1
            bit_length += 1
            # Each leaf node blocks twice the number of entries in next row
            blocked_entry_count *= 2

            # Shift off the value of this bit_length
            row_values = values.shift(frequency)

            row_values.each_with_index do |v, i|
                # Insert an entry in our hash using the binary tree path as our key
                table["%0#{bit_length}b" % (i + blocked_entry_count)] = v
            end

            # Keep track of how many leaf nodes we created so we don't use these positions in subsiquent rows
            blocked_entry_count += frequency
        end

        return table
    end

    # Extracts the quantization tables from the marker
    def parse_quantization_tables
        #NOTE
        #bit 0..3: number of QT (0..3, otherwise error)
        #bit 4..7: precision of QT, 0 = 8 bit, otherwise 16 bit
        tables = Hash.new
        @quantization_tables.each do |table|
            # Adobe likes to pack all the quantization tables together
            while(table.length > 0)
                info_byte = table.shift
                table_number = info_byte & 0x0F
                raise "Quantization table id > 3" if table_number > 3
                precision = info_byte& 0xF0 > 0 ? 16 : 8 

                if precision == 16
                    # Reinterpret the 64 chars into 32 shorts
                    data = table.shift(2 * 64) 
                    data = data.pack("C*").unpack("n*")
                else
                    data = table.shift(64)
                end
                tables[table_number] = { :data => data, :precision => precision }
            end
        end
        @quantization_tables = tables
    end

    def quantization_table_for_component(component)
        @quantization_tables[@samples[component][:quantization_table_id]][:data]
    end

    def member_by_member_multiply(lhs,rhs)
        result = Array.new(64)
        64.times do |i|
            result[i] = lhs[i] * rhs[i]
        end
        result
    end

    #TODO Blocks are encoded in a zig zag order, for 8x8 this order is 1,2,9,3,10,17....
    #     We need them in real order
    def zigzag_reorder(mcu_block)
        mcu_block
    end

    def reverse_dct(mcu_block)
        #TODO Research why no one explains the "DCT gain of 4"
        mcu_block.map! { |i| i / 4 }
        # Initialize our array to half our DC value instead of adding it everywhere later
        terms = mcu_block.length
        output = Array.new(terms, mcu_block[0] * 0.5)
        output.each_index do |index|
            1.upto(terms - 1) do |j|
                output[index] += mcu_block[j] * Math::cos( (Math::PI / terms) * j * ( index + 0.5))
            end
            output[index] = output[index].to_i
        end
        output
    end

    # Converts the macroblocks into pixels
    def macro_blocks_to_pixels
        @image = Array.new
        @macro_blocks.each_slice(3) do |y,b,r|
            # Get all the elements by making a deep copy
            y.length.times do |i|
                pixel_group = [y[i],b[i],r[i]]
                @image += pixel_group
            end
        end
        @image
    end

    def dct_to_ycrcb
        @macro_blocks = Array.new
        # Get the quantization tables
        y_quant_table = quantization_table_for_component(:y)
        b_quant_table = quantization_table_for_component(:cb)
        r_quant_table = quantization_table_for_component(:cr)

        @dct.each_slice(3) do |y,b,r|
            y = zigzag_reorder(y)
            b = zigzag_reorder(b)
            r = zigzag_reorder(r)
            y = member_by_member_multiply(y_quant_table,y)
            b = member_by_member_multiply(b_quant_table,b)
            r = member_by_member_multiply(r_quant_table,r)
            y = reverse_dct(y)
            b = reverse_dct(b)
            r = reverse_dct(r)
            @macro_blocks << y << b << r
        end
    end
end
