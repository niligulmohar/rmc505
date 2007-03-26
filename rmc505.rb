#! /usr/bin/env ruby

require 'logger'
require 'forwardable'
require 'yaml'
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
    if (index-@offset) < @elements.length
      return @elements[index-@offset]
    else
      @submaps.each do |r, o|
        if r.member?(index)
          return o[index]
        end
      end
      unmapped_element(index)
    end
  end
  def []=(index, value)
    if (index-@offset) < @elements.length
      return @elements[index-@offset].set(value)
    else
      @submaps.each do |r, o|
        if r.member?(index)
          return o[index] = value
        end
      end
      unmapped_element(index)
    end
  end
  def unmapped_element(index)
    fail
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
      fail if @elements.length > @submaps.map{ |r, o| r.first }.min
    end
  end
  def map(new_class = nil, &element_block)
    cls = new_class || self.class
    result = cls.new(@parent, @offset)
    result.elements = @elements.map(&element_block)
    result.submaps = @submaps.map do |range, submap|
      [range, submap.map(new_class, &element_block)]
    end
    return result
  end
end

class ByteParameter
  attr_reader :name, :range, :choices, :default
  attr_accessor :parent, :offset
  def initialize(name, range, choices = nil, default = nil)
    super()
    @name = name
    @range = range
    @choices = choices
    @default = default || range.first
  end
  def dump(indentataion, value)
    $logger.debug("#{'  '*indentataion}%8x | %2x | %s (%s)" % [@offset,
                                                               value,
                                                               @name,
                                                               @range])
  end
end

class ParameterStorage
  attr_reader :parameter, :value
  def initialize(parameter)
    fail unless parameter.kind_of?(ByteParameter)
    @parameter = parameter
    @value = @parameter.default
  end
  def set(value)
    unless @range.member?(value)
      dump
      $logger.error("Parameter value #{value} out of range")
    end
    @value = value
    dump
  end
  def dump(indentataion = 0)
    @parameter.dump(indentataion, @value)
  end
end

class ParameterData < SparseArray
  attr_accessor :map_parent
  def dump(indentation = 0)
    if @map_parent and @map_parent.name
      $logger.debug("#{'  '*indentation}#{@map_parent.name}")
    end
    @elements.each do |elt|
      elt.dump(indentation)
    end
    @submaps.each do |r, o|
      $logger.debug("#{'  '*(indentation+1)}(%8x...%8x)" % [r.first, r.last])
      o.dump(indentation + 1)
    end
  end
  def set_byte(offset, value)
    self[offset].set(value)
  end
end

class ParameterMap < SparseArray
  attr_reader :name
  attr_accessor :parameter_set_class, :list_entry, :box, :midi_channel, :midi_note

  def initialize(parent = nil, offset = 0, name = nil, &block)
    super(parent, offset, &block)
    @name = name
  end
  def map(cls)
    result = super
    result.map_parent = self
    return result
  end
  def new_data
    map(ParameterData) do |parameter|
      ParameterStorage.new(parameter)
    end
  end

  def param(*args)
    add(ByteParameter.new(*args))
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
    # $logger.debug("Comparing#{sysex_event.variable_data.hexdump}")
    # $logger.debug("       to" + "\xf0\x7e\0\x06\x02#{m}#{f}#{model}#{v}\xf7".hexdump)
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
  attr_reader :device_class, :parameter_data
  def initialize(device_class, sysex_channel, port)
    @device_class = device_class
    @sysex_channel = sysex_channel
    @port = port
    $logger.info("%s(%02x) --> Identity response from %s" % [@device_class.name,
                                                             @sysex_channel,
                                                             @port.ids])
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

  def name
    # "#{@device_class.name} (0x%02x) #{@port.ids}" % @sysex_channel
    @device_class.name
  end

  extend Forwardable
  def_delegators :@device_class, :identity_response_match?

  def sysex_match?(sysex_event)
    @device_class.sysex_match?(@sysex_channel, sysex_event)
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

require 'devices'

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

######################################################################

class MidiInterface
  def initialize
    @seq = Snd::Seq.open
    @seq.client_name = 'rmc505'
    @seq.nonblocking = true

    @port = @seq.create_simple_port('Listener',
                                    Snd::Seq::PORT_CAP_READ |
                                    Snd::Seq::PORT_CAP_WRITE |
                                    Snd::Seq::PORT_CAP_SUBS_READ |
                                    Snd::Seq::PORT_CAP_SUBS_WRITE,
                                    Snd::Seq::PORT_TYPE_MIDI_GENERIC)

    @connections = []
    connect

  end

  def new_connection(&block)
    @new_connection_block = block
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

    # Fake-connection:
    @port.event_output! do |event|
      event.direct!
      event.set_sysex("\xf0\x7e\x10\x06\x02\x41\x0b\x01\x03\x00\x00\x03\x00\x00\xf7")
    end
  end

  def pump
    event = nil
    while (event = @seq.event_input) do
      if event.sysex?
        if event.identity_response?
          port = Snd::Seq::Port.new(@seq, event.source_info)
          dest_port = Snd::Seq::DestinationPort.new(port, @port)
          new_connection = DeviceClass.connection(event, dest_port)
          if new_connection
            @connections << new_connection
            @new_connection_block.call(new_connection) if @new_connection_block
          else
            $logger.warn("#{event.source_ids} --> Unrecognized identity response (%d bytes)" %
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
            $logger.warn("#{event.source_ids} --> Unrecognized sysex (%d bytes)" %
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

######################################################################

def initialize_app(logdevice_class)
  $logger = Logger.new(logdevice_class.new(STDERR))
  $logger.datetime_format = "%H:%M:%S"

  $midi = MidiInterface.new

  yield $midi

  $midi.identity_request!
end

require 'gui'
