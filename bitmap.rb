#
# Author: Chris Lundquist <ChrisMLundquist@gmail.com>
#
# Description: 
# This class loads bitmap files facilitating their use
# with OpenGL
class Bitmap
    HEADER_SIZE = 14
    EXTENDED_HEADER_SIZE = 0x0E..0x11
    DATA_START = 0x0A..0x0D
    WIDTH = 0x12..0x15
    HEIGHT = 0x16..0x19
    COLOR_DEPTH = 0x1C..0x1D
    IMAGE_SIZE = 0x22..0x25
    NUMBER_OF_COLORS_IN_PALETTE = 0x2E..0x31

    attr_reader :width,:height,:color_depth,:data,:header, :file_name


    alias size_x width
    alias size_y height

    def initialize(file)
        @file_name = file
        case file
        when String
            open_file(file) 
        when File
            file.rewind
            @data = file.read
        else
            raise "Unable to create bitmap from #{file.class}"
        end
        parse_header()
        parse_bitmap()
    end

    def inspect
      "#@file_name #{@width}x#{@height} #@color_depth bit color"
    end

    private
    def open_file(file_path)
        f = File.open(file_path,"rb")

        # Read the file
        @data = f.read
        f.close
    end

    def parse_header
        # Get each attribute as an unsigned int
        @data_start = @data[DATA_START].unpack("I").first
        @header_size = @data[EXTENDED_HEADER_SIZE].unpack("I").first
        @width = @data[WIDTH].unpack("I").first
        @height = @data[HEIGHT].unpack("I").first
        @color_depth = @data[COLOR_DEPTH].unpack("S").first
        @image_size = @data[IMAGE_SIZE].unpack("I").first
        @num_palette_colors = @data[NUMBER_OF_COLORS_IN_PALETTE].unpack("I").first

        # For Formality
        @header = @data[0..@header_size]
        @color_palette = @data[@header_size + HEADER_SIZE..@data_start - 1].unpack("C*")
        @data = @data[@data_start..-1]
    end

    def translate_to_palette_colors
        color_map = Array.new 
        # Process the color map
        @color_palette.each_slice(4) do |b,g,r,a|
            # Sort it into the right order dropping alpha
            # color_map is now an array of arrays. So. color_map[1] => [ R,G,B ]
            color_map << [r,g,b]
        end
        @color_palette = color_map

        @data.map! { |i| @color_palette[i] }.flatten!
        @data
    end

    def parse_bitmap
        # Turn the string into an array
        @data = @data.unpack("C*")

        # Check if there is a palette we should be using
        unless @color_palette.empty?
            translate_to_palette_colors()
        else
            # No color palette so that means the color isn't indexed
            case @color_depth 
            when 24
                # Rearrange BGR -> RGB
                load_24bit()
            when 8
                # We need to expand each byte
                load_8bit()
            else
                raise "Unsupported Bit Depth of: #{@color_depth}" 
            end
        end

        # Turn it back into a string for memory effeciency
        @data = @data.pack("C*")
    end

    def load_24bit
        i = 0
        while i + 2 < @data.length
            # This rotates BGR -> RGB which makes it 'correct'
            @data[i], @data[i + 2] = @data[i + 2], @data[i]
            i += 3
        end
    end

    def expand_byte(value, mask, shift, max)
        (((value & mask) >> shift).to_f / max * 255).round
    end

    def load_8bit
        # R 0123 4567 & 0xE0 = 012x xxxx
        # G 0123 4567 & 0x1C = xxx3 45xx
        # B 0123 4567 & 0x03 = xxxx xx67
        @data.map! do |i|
            [r = expand_byte(i,0xE0,5,7), g = expand_byte(i,0x1C,2,7), b = expand_byte(i, 0x03, 0, 3)]
            #    [r = (i & 0x07), g = (i & 0x38), b = (i & 0xC0)]
        end.flatten!
    end
end

