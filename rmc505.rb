#! /usr/bin/env ruby

require 'logger'
require 'forwardable'
require 'Korundum'
$: << File.join(File.dirname(__FILE__), 'asound')
require 'asound'

######################################################################

class SparseArray
  attr_accessor :elements, :submaps
  def initialize(parent = nil, offset = 0)
    @parent = parent
    @offset = offset
    @elements = []
    @submaps = []
    yield self if block_given?
  end
  def [](index)
    if index < @elements.length
      return @elements[index]
    else
      @submaps.each do |r, o|
        if r.member?(index)
          return o[index]
        end
      end
      fail
    end
  end
  def end
    (@submaps.collect{ |r,o| r.last } + [@offset + @elements.length]).max
  end
  def length
    self.end - @offset
  end
  def offset(o = 0, *args, &block)
    add_submap_of_class(self.class, o, *args, &block)
  end
  def add(element)
    element.offset = @offset + @elements.length
    @elements.push(element)
    check_overlap!
  end
  def add_submap_of_class(cls, offset = 0, *args)
    submap = cls.new(self, offset, *args)
    yield submap if block_given?
    @submaps.push([(offset ... offset+submap.length), submap])
    check_overlap!
  end
  def check_overlap!
    if !@submaps.empty? && !@elements.empty?
      fail if @elements.length > @submaps.map{ |r,o| r.begin }.min
    end
  end
  def map(&element_block)
    result = self.class.new(@parent, @offset)
    result.elements = @elements.map(&element_block)
    result.submaps = @submaps.map do |range, submap|
      [range, submap.map(&element_block)]
    end
  end
end

class ByteParameter
  attr_accessor :parent
  attr_accessor :offset
  def initialize(name, range, choices = nil)
    super()
    @name = name
    @range = range
    @value = range.first
    @choices = choices
  end
  def default_value
  end
end

class ParameterStorage
end

class ParameterData < SparseArray

  def read_request(connection)
    if length > 127
      @submaps.each do |r, o|
        o.load
      end
    else
      # send_sysex(data_request(@offset, self.end - @offset))
    end
  end
  def write_request(connection)
  end

  def set_byte(offset, value)
    @submaps.each do |r, o|
      if r.member?(offset)
        o.write(offset, value)
        return
      end
    end
    #print "Unmapped parameter: %8x\n" % offset
  end
end

class ParameterMap < SparseArray
  attr_reader :name
  attr_accessor :trigger_channel
  attr_accessor :trigger_note

  def initialize(parent = nil, offset = 0, name = nil, &block)
    super(parent, offset, &block)
    @name = name
  end

  def new_data
    map do |parameter|
      ParameterStorage.new(parameter)
    end
  end

  def param(*args)
    add(ByteParameter.new(*args))
  end
  def subsets
    @submaps.collect{ |r, o| o }
  end

  def dump(indent = 0)
    if @name
      print "  " * indent
      print "%s\n" % @name
    end
    @submaps.each do |r, o|
      print "  " * (indent+1)
      print "(%8x...%8x)\n" % [r.first, r.last]
      o.dump(indent + 2)
    end
  end
end

class PatchName < ParameterData
end

class WaveParameter < ParameterData
end


######################################################################

class DeviceClass
  class << self
    def [](name)
      @@classes[name]
    end
    def connection(identity_response, port)
      @@classes.values.each do |cls|
        if cls.identity_response_match?(identity_response)
          return cls.new(identity_response.sysex_channel, port)
        end
      end
      return nil
    end
  end

  attr_reader :name
  def initialize(name)
    @@classes ||= {}
    @@classes[name] = self
    @name = name
    yield self
  end
  def new(sysex_channel, port)
    DeviceConnection.new(self, sysex_channel, port)
  end
  def identity_response_match?(sysex_event)
    m, f, model, v = manufacturer_id.chr, family_code, model_number, version_number
    return sysex_event.variable_data =~ /^\xf0\x7e.\x06\x02#{m}#{f}#{model}#{v}\xf7$/
  end
  def parameter_map(&block)
    if @parameter_map
      @parameter_map
    elsif block_given?
      @parameter_map = ParameterMap.new(&block)
    end
  end
end

class DeviceConnection
  def initialize(device_class, sysex_channel, port)
    @device_class = device_class
    @sysex_channel = sysex_channel
    @port = port
    $logger.info("%s(%02x) --> Identity response on %s" % [@device_class.name,
                                                           @sysex_channel,
                                                           port.ids])
    if device_class.parameter_map
      @parameter_data = device_class.parameter_map.new_data
    end
  end
  def send_sysex(data)
    $logger.debug("%s(%02x) <-- %s" % [@device_class.name,
                                       @sysex_channel,
                                       data.hexdump])
    @port.output_event! do |event|
      ev.direct!
      ev.set_sysex(data)
    end
  end
  def send_read_data_request(start, length)
    send_sysex(@device_class.read_data_request(@sysex_channel, start, length))
  end
  def send_write_data_request(start, data)
    send_sysex(@device_class.write_data_request(@sysex_channel, start, length))
  end

  extend Forwardable
  def_delegators :@device_class, :identity_response_match?

  def sysex_match?(sysex_event)
    @device_class.sysex_match?(@sysex_channel, event)
  end
  def recieve_sysex(sysex_event)
    if @device_class.read_data_response?(sysex_event)
      recieve_data(*@device_class.parse_data_response(sysex_event))
    else
      $logger.warn("%s(%02x) --> Unrecognized sysex" % [@device_class.name,
                                                        @sysex_channel])
    end
  end
  def recieve_data(start, data)
  end
end

######################################################################

module RolandSysex
  def manufacturer_id() 0x41 end
  def self.checksum(data)
    sum = 0
    data.each_byte { |b| sum += b }
    return 128 - sum % 128
  end
  def read_data_request(sysex_channel, start, length)
    head = "\xf0\x41#{sysex_channel.chr}\x00\x0b\x11"
    msg = [addr, size].pack('NN')
    tail = [checksum(msg), 0xf7].pack('CC')
    return head + msg + tail
  end
  def write_data_request(sysex_channel, start, data)
    head = "\xf0\x41#{sysex_channel.chr}\x00\x0b\x12"
    msg = [addr].pack('N') + data
    tail = [checksum(msg), 0xf7].pack('CC')
    return head + msg + tail
  end
  def sysex_match?(sysex_channel, event)
    event.variable_data =~ /^\xf0#{MANUFACTURER_ID}#{sysex_channel.chr}\x00\x0b\x12$/
  end
end

DeviceClass.new('PCR-A30') do |c|
  class << c
    include RolandSysex
    def family_code() "\x62\x01" end
    def model_number() "\x00\x00" end
    def version_number() "\x01\x01\x00\x00" end
  end
end

DeviceClass.new('D2') do |c|
  class << c
    include RolandSysex
    def family_code() "\x0b\x01" end
    def model_number() "\x03\x00" end
    def version_number() "\x00\x03\x00\x00" end
  end
  KEYFOLLOW = %w[-100 -70 -50 -30 -10 0 +10 +20 +30 +40 +50 +70 +100 +120 +150 +200]
  KEYFOLLOW2 = %w[-100 -70 -50 -40 -30 -20 -10 0 +10 +20 +30 +40 +50 +70 +100]
  WAVE_GAIN = %w[-6 0 +6 +12]
  RANDOM_PITCH_DEPTH = %w[0 1 2 3 4 5 6 7 8 9 10 20 30 40 50 60 70 80 90 100 200 300 400 500 600 700 800 900 1000 1100 1200]
  FILTER_TYPE = %w[Off LPF BF HPF PRG]
  HF_DAMP = %w[200 250 315 400 500 630 800 1000 1250 1600 2000 2500 3150 4000 5000 6300 8000 Bypass]
  MFX_TYPE = ['4 band EQ',
              'Spectrum',
              'Enhancer',
              'Overdrive',
              'Distortion',
              'Lo-Fi',
              'Noise',
              'Radio tuning',
              'Phonograph',
              'Compressor',
              'Limiter',
              'Slicer',
              'Tremolo',
              'Phaser',
              'Chorus',
              'Space-D',
              'Tetra chorus',
              'Flanger',
              'Stereo flanger',
              'Short delay',
              'Auto pan',
              'FB pitch shifter',
              'Reverb',
              'Gate reverb',
              'Isolator']
  c.parameter_map do |p|
    p.offset(0x02_00_00_00, 'Patches') do |g0|
      7.times do |n0|
        g0.offset(0x01_00_00 * n0, "Patch #{n0 + 1}") do |g1|
          # g1.trigger_channel = n0
          g1.offset(0, 'Common') do |g2|
            g2.add_submap_of_class(PatchName)
            g2.offset(0x31) do |r|
              r.param('Bend range up', (0..12))
              r.param('Bend range down', (0..48))
              r.param('Solo switch', (0..1), %w[Off On])
              r.param('Solo legato switch', (0..1), %w[Off On])
              r.param('Portamento switch', (0..1), %w[Off On])
              r.param('Portamento mode', (0..1), %w[Normal Legato])
              r.param('Portamento type', (0..1), %w[Rate Time])
              r.param('Portamento start', (0..1), %w[Pitch Note])
              r.param('Portamento time', (0..127))
            end
            g2.offset(0x40) do |r|
              r.param('Velocity range switch', (0..1), %w[Off On])
            end
            g2.offset(0x42) do |r|
              r.param('Stretch tune depth', (0..3), %w[Off 1 2 3])
              r.param('Voice priority', (0..1), %w[Last Loudest])
              r.param('Structure type 1/2', (0..9))
              r.param('Booster 1/2', (0..3), %w[0 +6 +12 +18])
              r.param('Structure type 3/4', (0..9))
              r.param('Booster 3/4', (0..3), %w[0 +6 +12 +18])
            end
          end
          4.times do |n1|
            g1.offset(0x1000 + 0x200 * n1, "Tone #{n1}") do |g2|
              g2.offset(0) do |r|
                r.param('Tone switch', (0..1), %w[Off On])
              end
              g2.add_submap_of_class(WaveParameter, 1)
              g2.offset(5) do |r|
                r.param('Wave gain', (0..3), WAVE_GAIN)
                r.param('FXM switch', (0..1), %w[Off On])
                r.param('FXM color', (0..3))
                r.param('FXM depth', (0..15))
              end
              g2.offset(0xb) do |r|
                r.param('Velocity crossfade', (0..127))
                r.param('Velocity range lower', (1..127))
                r.param('Velocity range upper', (1..127))
                r.param('Keyboard range lower', (0..127))
                r.param('Keyboard range upper', (0..127))
              end
              g2.offset(0x15) do |r|
                ['Modulation', 'Pitch bend', 'Aftertouch'].each do |modtype|
                  4.times do |modn|
                    r.param("#{modtype} #{modn+1} destination", (0..15), %w[Off PCH CUT RES LEV PAN L1P L2P L1F L2F L1A L2A PL1 PL2 L1R L2R])
                    r.param("#{modtype} #{modn+1} depth", (0..127))
                  end
                end
                2.times do |lfon|
                  r.param("LFO#{lfon+1} waveform", (0..7), %w[TRI SIN SAW SQR TRP S&H RND CHS])
                  r.param("LFO#{lfon+1} key sync", (0..1))
                  r.param("LFO#{lfon+1} rate", (0..127))
                  r.param("LFO#{lfon+1} offset", (0..4), %w[-100 -50 0 +50 +100])
                  r.param("LFO#{lfon+1} delay time", (0..127))
                  r.param("LFO#{lfon+1} fade mode", (0..3), %w[ON-IN ON-OUT OFF-IN OFF-OUT])
                  r.param("LFO#{lfon+1} fade time", (0..127))
                  r.param("LFO#{lfon+1} tempo sync", (0..1), %w[Off On])
                end
                r.param('Coarse tune', (0..96))
                r.param('Fine tune', (0..100))
                r.param('Random pitch depth', (0..30), RANDOM_PITCH_DEPTH)
                r.param('Pitch key follow', (0..15), KEYFOLLOW)
                r.param('Pitch envelope depth', (0..24))
                r.param('Pitch envelope velocity sens', (0..125))
                r.param('Pitch envelope velocity time 1', (0..14), KEYFOLLOW2)
                r.param('Pitch envelope velocity time 4', (0..14), KEYFOLLOW2)
                r.param('Pitch envelope time key follow', (0..14), KEYFOLLOW2)
                4.times do |n2|
                  r.param("Pitch envelope time #{n2}", (0..127))
                end
                4.times do |n2|
                  r.param("Pitch envelope level #{n2}", (0..126))
                end
                r.param('Pitch LFO1 depth', (0..126))
                r.param('Pitch LFO2 depth', (0..126))

                r.param('Filter type', (0..4), FILTER_TYPE)
                r.param('Cutoff frequency', (0..127))
                r.param('Cutoff key follow', (0..15), KEYFOLLOW)
                r.param('Resonance', (0..127))
                r.param('Resonance velocity sens', (0..125))
                r.param('Filter envelope depth', (0..126))
                r.param('Filter envelope velocity curve', (0..6))
                r.param('Filter envelope velocity sens', (0..125))
                r.param('Filter envelope velocity time 1', (0..14), KEYFOLLOW2)
                r.param('Filter envelope velocity time 4', (0..14), KEYFOLLOW2)
                r.param('Filter envelope time key follow', (0..14), KEYFOLLOW2)
                4.times do |n2|
                  r.param("Filter envelope time #{n2}", (0..127))
                end
                4.times do |n2|
                  r.param("Filter envelope level #{n2}", (0..127))
                end
                r.param('Filter LFO1 depth', (0..126))
                r.param('Filter LFO2 depth', (0..126))

                r.param('Tone level', (0..127))
                r.param('Bias direction', (0..3), %w[Lower Upper Low&Up All])
                r.param('Bias point', (0..127))
                r.param('Bias level', (0..14), KEYFOLLOW2)
                r.param('Amp envelope velocity curve', (0..6))
                r.param('Amp envelope velocity sens', (0..125))
                r.param('Amp envelope velocity time 1', (0..14), KEYFOLLOW2)
                r.param('Amp envelope velocity time 4', (0..14), KEYFOLLOW2)
                r.param('Amp envelope time key follow', (0..14), KEYFOLLOW2)
                4.times do |n2|
                  r.param("Amp envelope time #{n2}", (0..127))
                end
                3.times do |n2|
                  r.param("Amp envelope level #{n2}", (0..127))
                end
                r.param('Amp LFO1 depth', (0..126))
                r.param('Amp LFO2 depth', (0..126))
                r.param('Tone pan', (0..127))
                r.param('Pan key follow', (0..14), KEYFOLLOW2)
                r.param('Random pan', (0..63))
                r.param('Alternate pan depth', (1..127))
                r.param('Pan LFO1 depth', (0..126))
                r.param('Pan LFO2 depth', (0..126))
              end
            end
          end
        end
      end
    end
  end
end



module YamahaSysex
  def manufacturer_id() 0x43 end
end

DeviceClass.new('MU50') do |c|
  class << c
    include YamahaSysex
    def family_code() "\x00\x41" end
    def model_number() "\x46\x01" end
    def version_number() "\x00\x00\x00\x01" end
  end
end

######################################################################

class String
  def hexdump
    result = ''
    each_byte do |byte|
      result += " %02x" % byte
    end
    return result
  end
end

$logger = Logger.new(STDERR)

######################################################################

class MidiInterface
  def initialize
    @seq = Snd::Seq.open
    @seq.client_name = 'rmc505'

    @port = @seq.create_simple_port('Listener',
                                    Snd::Seq::PORT_CAP_READ |
                                    Snd::Seq::PORT_CAP_WRITE |
                                    Snd::Seq::PORT_CAP_SUBS_READ |
                                    Snd::Seq::PORT_CAP_SUBS_WRITE,
                                    Snd::Seq::PORT_TYPE_MIDI_GENERIC)

    @connections = []
    connect
  end

  def connect
    @seq.each_port do |port|
      if port.midi? && port.read_subscribable? && port.write_subscribable?
        $logger.debug("Connecting to #{port.client}:#{port.port}")
        @port.connect_from(port)
        @port.connect_to(port)
      end
    end
  end

  def broadcast!
    ev = Snd::Seq::Event.new
    ev.source = @port
    ev.to_port_subscribers!
    ev.direct!
    yield ev
    @seq.event_output(ev)
    @seq.drain_output
  end

  def identity_request!
    broadcast! do |event|
      event.set_sysex("\xf0\x7e\x7f\x06\x01\xf7")
      $logger.debug("* <-- Identity request")
    end
  end

  def pump
    event = nil
    while (event = @seq.event_input) do
      if event.sysex?
        if event.identity_response?
          dest_port = Snd::Seq::DestinationPort.new(Snd::Seq::Port.new(@seq, event.source_info), @port)
          new_connection = DeviceClass.connection(event, dest_port)
          if new_connection
            @connections << new_connection
          else
            $logger.warn("? --> Unrecognized identity response (%d bytes)" %
                         event.variable_data.length)
            $logger.debug("      #{event.variable_data.hexdump}")
          end
        else
          catch :recognized do
            @connections.each do |conn|
              if conn.sysex_match?(event)
                conn.recieve_sysex(event)
                throw :recognized
              end
            end
            $logger.warn("? --> Unrecognized sysex (%d bytes)" %
                         event.variable_data.length)
            $logger.debug("      #{event.variable_data.hexdump}")
          end
        end
      elsif not event.clock?
        $logger.debug("? --> MIDI #{event.type}")
      end
    end
  end
end

begin
  $midi = MidiInterface.new
  $midi.identity_request!
  loop do
    $midi.pump
  end
rescue Interrupt
end
