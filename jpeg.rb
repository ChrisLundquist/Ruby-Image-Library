require 'btree'
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

    attr_reader :start_of_image, 
        :start_of_frame, 
        :huffman_tables, 
        :quantization_tables,
        :restart_interval,
        :start_of_scan,
        :restart,
        :appication_specific,
        :comment,
        :file,          # The File (handle) to our object
        :file_path,     # The string file path of our image
        :height,        # height of the image
        :width,         # width of the image
        :color_space

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
        parse_header()
    end

    def new_from_path
        @file = File.open(@file_path)
        new_from_file()
    end

    # needs a better name
    def parse_header
        while header = @file.read(2)
            marker, type = header.unpack("CC")

            raise "marker error" unless marker == 0xFF

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
                @scan = read_entropy_encoded_segment()
            when RESTART
            when APPLICATION_SPECIFIC  # 224..240
                @application_specific << read_data_segment()
            when COMMENT
            when END_OF_IMAGE
                # All Done
            else
                raise "unrecognized marker"
                # We have an unrecognized method, we will try to fetch it's data
                #read_data_segment()
            end
        end

        # We have read and parsed the file into markers and segments, now interpret each 
        parse_start_of_frame()
        parse_quantization_tables()
        parse_huffman_tables()
    end

    # Reads the first two bytes after a marker to see how much to read
    # then returns the unpacked data for the segment
    def read_data_segment
        len = @file.read(2).unpack("n").first

        data = @file.read(len - 2) or
        raise "Could not fetch data segment"
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

        # these 2 bytes are interpretted together as a short
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

        # helper function that unpacks the sample ratio
        # sampling factors (bit 0-3 vert., 4-7 hor.)
        get_sample_ratio = lambda { |sample_byte| return Rational(sample_byte & 0x0F, sample_byte & 0xF0 >> 4) } 

        @start_of_frame[6..-1].each_slice(3) do |component_id, sample_factors, quantization_table_id|
            case component_id 
            when 1 # Y
                @samples[:y]  = { :ratio => get_sample_ratio.call(sample_factors), :quantization_table_id => quantization_table_id }
            when 2 # Cb
                @samples[:cb] = { :ratio => get_sample_ratio.call(sample_factors), :quantization_table_id => quantization_table_id }
            when 3 # Cr
                @samples[:cr] = { :ratio => get_sample_ratio.call(sample_factors), :quantization_table_id => quantization_table_id }
            when 4 # I ????
                @samples[:i] = { :ratio => get_sample_ratio.call(sample_factors), :quantization_table_id => quantization_table_id }
            when 5 # Q ????
                @samples[:q] = { :ratio => get_sample_ratio.call(sample_factors), :quantization_table_id => quantization_table_id }
            else 
                raise "Unrecognized component in start of frame segment"
            end
        end
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
            # each_with_index starts at 0, but our frequency table starts at 1
            bit_length += 1
            # each leaf node blocks twice the number of entries in next row
            blocked_entry_count *= 2

            # shift off the value of this bit_length
            row_values = values.shift(frequency)

            row_values.each_with_index do |v, i|
                # Insert an entry in our hash using the binary tree path as our key
                table["%0#{bit_length}b" % (i + blocked_entry_count)] = v
            end

            # keep track of how many leaf nodes we created so we don't use these positions in subsiquent rows
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

    def get_start_of_scan
    end
end
