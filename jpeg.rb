class JPEG
    FILE_MAGIC_NUMBER = [0xFF,0xD8]    # to validate we are opening a JPEG file
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

    # converts the instance to a Bitmap object
    def to_bmp
    end

    # writes the object to disk
    def save(file_path = @file_path) # default to the file we opened
    end
    alias :write_file :save

    private 
    def new_from_file
        parse_markers()

        # Tells us our color space and dimensions
        parse_start_of_frame()
        # The quantization tables to use
        parse_quantization_tables()
        # The huffman tables
        parse_huffman_tables()
        parse_start_of_scan()

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
            when DEFINE_HUFFMAN_TABLES      # 196
                @huffman_tables << read_data_segment()
            when DEFINE_QUANTIZATION_TABLES # 219
                @quantization_tables << read_data_segment()
            when DEFINE_RESTART_INTERVAL
            when START_OF_SCAN
                @start_of_scan = read_entropy_encoded_segment()
            when RESTART
            when APPLICATION_SPECIFIC  # 224..240
                @application_specific << read_data_segment()
            when COMMENT
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

        @color_space = case @start_of_frame[5]
                       when 1
                           :grey
                       when 3
                           :ycbcr
                       when 4
                           :cmyk
                       else
                           :unkown
                       end
        @samples = Hash.new

        # Helper function that unpacks the sample ratio
        # Sampling factors (bit 0-3 vert., 4-7 hor.)
        get_sample_ratio = lambda { |sample_byte| return Rational(sample_byte & 0x0F, sample_byte & 0xF0 >> 4) } 

        @start_of_frame[6..-1].each_slice(3) do |component_id, sample_factors, quantization_table_id|
            @samples[component_id_to_symbol(component_id)]  = { :ratio => get_sample_ratio.call(sample_factors), :quantization_table_id => quantization_table_id }
        end
    end

    def component_id_to_symbol(id)
        case id
        when 1
            :y
        when 2
            :cb
        when 3
            :cr
        when 4
            :i
        when 5
            :q
        else
            raise "Unrecognized component in start of frame segment"
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
        @data = @start_of_scan

        # The first two bytes of the segment is the length of this scan
        length_high, length_low = @data.shift(2)
        length = (length_high << 8) + length_low

        @start_of_scan = @data.shift(length)

        number_of_components_to_scan = @start_of_scan.shift()
        raise "Invalid number of components to scan: #{number_of_components_to_scan}" unless (1..4).include?(number_of_components_to_scan)

        scan_table = Hash.new

        number_of_components_to_scan.times do |component|
            component_id, huffman_table = @start_of_scan.shift(2)
            ac_huffman_table_id = huffman_table & 0x0F
            dc_huffman_table_id = (huffman_table & 0xF0) >> 4
            scan_table[component_id_to_symbol(component_id)] = { :ac_id => ac_huffman_table_id, :dc_id => dc_huffman_table_id} 
        end
        # The scan table tells us which huffman table to use for each component
        @start_of_scan = scan_table
    end

    def parse_huffman_tables
        tables = Hash.new
        tables[:ac] = Hash.new
        tables[:dc] = Hash.new
        #
        #  HT information (1 byte):
        #  bit 0..3: number of HT (0..3, otherwise error)
        #  bit 4   : type of HT, 0 = DC table, 1 = AC table
        #  bit 5..7: not used, must be 0

        # Find the type and ID of each huffman table
        @huffman_tables.each do |table|
            table_id = table.first & 0x07 # this SHOULD be 0..3 but sometimes adobe does what they want
            ac_table = (table.first & 0x10) > 0
            table_type = ac_table ? :ac : :dc
            tables[table_type][table_id] = build_huffman_hash(table[1..16],table[17..-1])
        end
        @huffman_tables = tables
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


    def parse_quantization_tables
        #NOTE
        #bit 0..3: number of QT (0..3, otherwise error)
        #bit 4..7: precision of QT, 0 = 8 bit, otherwise 16 bit
        tables = Hash.new
        @quantization_tables.each do |table|
            table_number = table.first & 0x0F
            raise "Quantization table id > 3" if table_number > 3
            precision = table.first & 0xF0 > 0 ? 16 : 8 

            if precision == 16
                #TODO reinterpret the 64 bytes into 32 shorts
            end
            tables[table_number] = { :data => table[1..-1], :precision => precision }
        end
        @quantization_tables = tables
    end
end
