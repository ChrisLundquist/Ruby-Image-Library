class JPEG
    FILE_MAGIC_NUMBER = [0xFF,0xD8]   # to validate we are opening a JPEG file
    START_OF_IMAGE = 0xD8             # Marker ending
    START_OF_FRAME = 0xC0             # baseline DCT
    PROGRESSIVE_START_OF_FRAME = 0xC2 # Progressive DCT
    DEFINE_HUFFMAN_TABLES = 0xC4      # Specifies one or more Huffman tables
    DEFINE_QUANTIZATION_TABLES = 0xDB # Specified one or more quantization tables
    DEFINE_RESTART_INTERVAL = 0xDD    # Specifies the interval between rST n markers in macroblocks.
    START_OF_SCAN = 0xDA              #
    RESTART = 0xD7                    # Inserted every r macroblocks where r is the restart interval set by a DRI marker
    APPLICATION_SPECIFIC = 0xE0       #
    COMMENT = 0xFE                    # Contains a text comment
    END_OF_IMAGE = 0xD9               #

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
            raise "marker error" unless marker == 0xFF

            case type
            when START_OF_IMAGE
                # Do nothing
            when START_OF_FRAME
            when PROGRESSIVE_START_OF_FRAME
            when DEFINE_HUFFMAN_TABLES
            when DEFINE_QUANTIZATION_TABLES
            when DEFINE_RESTART_INTERVAL
            when START_OF_SCAN
            when RESTART
            when APPLICATION_SPECIFIC
            when COMMENT
            when END_OF_IMAGE
            else
                # We have an unrecognized method, we will try to fetch it's data
                len = @file.read(2).unpack("n").first

                data = @file.read(len - 2) or
                    raise "Could not fetch data segment"
                data = data.unpack("C*")
            end
        end
    end

    def check_file_type
    end

    def get_start_of_image
    end

    def get_start_of_frame
    end

    def get_huffman_tables
    end

    def get_quantization_tables
    end

    def get_start_of_scan
    end

    def get_application_specific
    end

    def get_comment
    end
end
