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
        :end_of_image,
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

            puts "Reading marker #{type} @ #{@file.pos}"
            #TODO raise "marker error" unless marker == 0xFF

            case type
            when START_OF_IMAGE             # 216
                # Do nothing
            when START_OF_FRAME             # 192
                puts "start of frame"
                @start_of_frame = read_data_segment()
                parse_start_of_frame()
            when PROGRESSIVE_START_OF_FRAME
            when DEFINE_HUFFMAN_TABLES      # 196
                puts "huffman table"
                @huffman_tables << read_data_segment()
            when DEFINE_QUANTIZATION_TABLES # 219
                puts "quant table"
                @quantization_tables << read_data_segment()
            when DEFINE_RESTART_INTERVAL
            when START_OF_SCAN
                puts "start of scan"
            when RESTART
            when APPLICATION_SPECIFIC  # 224..240
                puts "app specific"
                @application_specific << read_data_segment()
            when COMMENT
            when END_OF_IMAGE
                # All Done
            else
                puts "Unkown marker"
                # We have an unrecognized method, we will try to fetch it's data
                read_data_segment()
            end
        end
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

    def parse_start_of_frame
        puts "parsing start of frame"
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
        @start_of_frame[6..-1].each_slice(3) do |component_id, sample_factors, quantization_table_id|
        # sampling factors (bit 0-3 vert., 4-7 hor.)
            case component_id 
            when 1 # Y
                luminance_sample_ratio = Rational(sample_factors & 0x0F, sample_factors & 0xF0) 
            when 2 # Cb
            when 3 # Cr
            when 4 # I ????
            when 5 # Q ????
            else 
                raise "Unrecognized component in start of frame segment"
            end
        end
    end

    def parse_huffman_tables
    end

    def parse_quantization_tables
    end

    def get_start_of_scan
    end
end
