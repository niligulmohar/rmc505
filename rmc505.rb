#! /usr/bin/env ruby

require 'asound'
require 'Korundum'

######################################################################

class ByteParameter < Qt::Object
  slots 'change(int)'
  attr_accessor :parent
  attr_accessor :offset
  def initialize(name, range, choices = nil)
    super()
    @name = name
    @range = range
    @value = range.first
    @choices = choices
  end
  def load
    send_sysex(data_request(@offset, 1))
  end
  def write(value)
    unless @range.member?(value)
      dump
      raise 'Parameter (%d) out of range' % value
    end
    @value = value
    dump
    if @slider
      @slider.value = @value
    end
  end
  def change(value)
    if value != @value
      write(value)
      send_sysex(data_set(@offset, @value.chr))
      auto_trigger
    end
    if @combo
      @combo.set_current_item(@value)
    end
  end
  def read
    return @value
  end
  def dump(indent = 0)
    print "  " * indent
    print "%8x | %2x | %s (%s)\n" % [@offset, @value, @name, @range]
  end
  def build_widgets(parent)
    @label = Qt::Label.new(@name, parent)
    box = Qt::HBox.new(parent)
    @slider = Qt::Slider.new(@range.first, @range.last, 1, @value, Qt::Slider::Horizontal, box)
    @slider.tick_interval = 1
    @slider.tickmarks = Qt::Slider::Below
    @slider.value = @value
    connect(@slider, SIGNAL('valueChanged(int)'), self, SLOT('change(int)'))
    if @choices
      @combo = Qt::ComboBox.new(box)
      @combo.insert_string_list(@choices)
      @combo.set_current_item(@value)
      connect(@combo, SIGNAL('activated(int)'), @slider, SLOT('setValue(int)'))
    end
  end
  def auto_trigger
    ref = @parent
    loop do
      break if ref.respond_to?(:trigger_channel) and ref.trigger_channel
      if ref.respond_to?(:parent)
        ref = ref.parent
      else
        return
      end
    end
    $note_trigger.auto_trigger(ref.trigger_channel, ref.trigger_note)
  end
end

# Subclassing a subclass of Qt::Object causes strange problems

module ParameterRangeMod
  attr_accessor :parent
  attr_reader :offset
  def add(parameter)
    parameter.offset = @offset + @parameters.length
    @parameters.push(parameter)
    parameter.parent = self
  end
  def length
    return @parameters.length
  end
  def load
    send_sysex(data_request(@offset, @parameters.length))
  end
  def write(offset, value)
    @parameters[offset - @offset].write(value)
  end
  def read(offset)
    @parameters[offset].read
  end
  def dump(indent = 0)
    @parameters.each do |p|
      p.dump(indent+1)
    end
  end
  def build_widgets(parent)
    @parameters.each do |p|
      p.build_widgets(parent)
    end
  end
end

class ParameterRange
  include ParameterRangeMod
  def initialize(offset)
    @offset = offset
    @parameters = []
  end
end

class ReservedParameterRange
  include ParameterRangeMod
  attr_accessor :length
  def initialize(offset)
    @offset = offset
    @length = 1
  end
  def write(offset, value)
  end
  def build_widgets(parent)
  end
end

WAVENAMES = ["TB Dst Saw",
  "TB Dst Sqr 1",
  "TB Dst Sqr 2",
  "TB Reso Sqr 1",
  "TB Reso Sqr 2",
  "TB Saw",
  "TB Solid Saw 1",
  "TB Solid Saw 2",
  "TB Square 1",
  "TB Square 2",
  "TB Sqr Decay",
  "TB Natural",
  "JP8000 Saw 1",
  "JP8000 Saw 2",
  "MG Saw",
  "Synth Saw 1",
  "JP-8 Saw",
  "P5 Saw",
  "Synth Saw 2",
  "OB Saw",
  "D-50 Saw",
  "JP-6 Square",
  "MG Square",
  "P5 Square",
  "JP-8 Pulse",
  "JP-6 Pulse",
  "MG Pulse",
  "260 Pulse",
  "JU-2 Sub OSC",
  "Frog wave",
  "Digiwave",
  "FM Pulse",
  "JP8000 PWM",
  "JP8000 FBK",
  "260 Sub OSC",
  "Dist Synth",
  "Dist Square",
  "MG Triangle",
  "Jungle Bass",
  "260 Sine Bs",
  "MC-202 Bass",
  "SH-101 Bass",
  "Octa Bass",
  "Funky Bass",
  "Poly Bass",
  "MG Bass",
  "FM Super Bass",
  "Solid Bass",
  "Organ Bass",
  "Dirty Bass",
  "Upright Bass",
  "Ac Bass",
  "Voco Bass",
  "Fingered Bass",
  "Pick Bass",
  "Fretless Bass",
  "Slap Bass",
  "Juno Rave",
  "Blaster",
  "Fat JP-6",
  "OB Strings",
  "Orch Strings",
  "Pizzy Techno",
  "Choir",
  "Syn Vox 1",
  "Syn Vox 2",
  "Syn Vox 3",
  "Ac Piano",
  "D-50 EP",
  "E Piano",
  "Clavi",
  "Full Stop",
  "FM Club Org",
  "E Organ 1",
  "E Organ 2",
  "Church Org",
  "Power B fst",
  "Power B slw",
  "Org Chord",
  "Tabular",
  "Glockenspiel",
  "Vibraphone",
  "FantabellSub",
  "DIGI Bell",
  "Steel Drum",
  "Marimba",
  "Balaphone",
  "Kalimba",
  "Steel Gtr",
  "Clean TC",
  "Dst Solo Gtr",
  "Dist Tek Gtr",
  "Gtr FX",
  "Harmo Gtr",
  "Wah Gtr 1",
  "Wah Gtr 2",
  "Wah Gtr 2a",
  "Wah Gtr 2b",
  "Wah Gtr 2c",
  "Wah Gtr 2d",
  "Sitar",
  "Brass",
  "Trumpet",
  "Mute Trumpet",
  "Soprano Sax",
  "Solo Sax",
  "Baritone Sax",
  "Brass Fall",
  "Flute",
  "Pan Flute",
  "Shakunichi",
  "Bagpipe",
  "Breath",
  "FeedbackWave",
  "Atmosphere",
  "Reso Noise",
  "MG White Nz",
  "P5 Noise",
  "MG Pink Nz",
  "Bomb Noise",
  "Sea",
  "Brush Noise",
  "Space Noise",
  "Scream",
  "Jet Plane",
  "Toy Gun 1",
  "Crash",
  "Toy Gun 2",
  "Toy Gun 3",
  "Emergency",
  "Buzzer",
  "Insect",
  "Tonality",
  "Ring OSC",
  "Reso FX",
  "Scratch Menu",
  "Vinyl Noise",
  "Scratch BD f",
  "Scratch BD r",
  "Scratch SD f",
  "Scratch SD r",
  "Scratch Alt",
  "Tape Rewind",
  "Vinyl Stop",
  "Hit Menu",
  "MG Blip",
  "Beam HiQ",
  "MG Attack",
  "Air Blip",
  "Org Click",
  "Syn Hit",
  "Techno Scene",
  "Techno Chord",
  "Dist Hit",
  "Thin Beef",
  "Tekno Hit",
  "Back Hit",
  "TAO Hit",
  "Phily Hit",
  "INDUST MENU",
  "Analog Bird",
  "Retro UFO",
  "PC-2 Machine",
  "Hoo",
  "Metal Sweep",
  "Afro Feet",
  "Bomb",
  "Bounce",
  "Electric Dunk",
  "Iron Door",
  "Dist Swish",
  "Drill Hit",
  "Thrill",
  "PCM Press",
  "Air Gun",
  "Voice Menu",
  "One!",
  "Two!",
  "Three!",
  "Kick it!",
  "Come on!",
  "Wao!",
  "Shout",
  "Ooh! 1",
  "Ooh! 2",
  "Voice Loop",
  "Pa!",
  "Canvas",
  "Punch",
  "Chiki!",
  "Hey!",
  "Laugh",
  "Aah Formant",
  "Eeh Formant",
  "Iih Formant",
  "Ooh Formant",
  "Uuh Formant",
  "Dist Ooh Vox",
  "Auh Voice",
  "Stream",
  "Bird",
  "Tom Menu",
  "TR909 Tom",
  "TR909 DstTom",
  "TR808 Tom",
  "TR606 Tom",
  "TR606 CmpTom",
  "TR707 Tom",
  "Syn Tom",
  "Deep Tom",
  "Can Tom",
  "Kick Tom",
  "Natural Tom",
  "PERCUS MENU1",
  "PERCUS MENU2",
  "TR808 Conga",
  "HiBongo Open",
  "LoBongo Open",
  "HiConga Mute",
  "HiConga Open",
  "LoConga Open",
  "HiBongo LoFi",
  "LoBongo Lofi",
  "HiConga Mt LF",
  "HiConga Op LF",
  "Loconga LoFi",
  "Timpani",
  "Mute Surdo",
  "Open Surdo",
  "Hi Timbale",
  "Lo Timbale",
  "Hi Timbale LF",
  "Lo Timbale LF",
  "Tabla",
  "TablaBaya",
  "Udo",
  "AfroDrum Rat",
  "ChenChen",
  "Op Pandeiro",
  "Mt Pandeiro",
  "Tambourine 1",
  "Tambourine 2",
  "Tambourine 3",
  "Tambourine 4",
  "CR78 Tamb",
  "Cowbell MENU",
  "TR808Cowbell",
  "TR707Cowbell",
  "CR78Cowbell",
  "Cowbell",
  "TR727 Agogo",
  "CR78 Beat",
  "Triangle 1",
  "Triangle 2",
  "SHKR+ Menu",
  "808 Maracas",
  "Maracas",
  "Cabasa Up",
  "TechnoShaker",
  "TR626Shaker",
  "DanceShaker",
  "CR78 Guiro",
  "Long Guiro",
  "Short Guiro",
  "Mute Cuica",
  "Open Cuica",
  "Whistle",
  "TR727Quijada",
  "Jingle Bell",
  "Belltree",
  "Wind Chime",
  "RIM MENU",
  "TR909 RIM",
  "TR808 RIM",
  "TR808 RimLng",
  "TR707 Rim",
  "Analog Rim",
  "Natural Rim",
  "Ragga Rim 1",
  "Lo-Fi Rim",
  "Wood Block",
  "Jungle Snap",
  "TR808 Claves",
  "Hyoshigi",
  "CHH MENU 1",
  "CHH MENU 2",
  "TR909 CHH 1",
  "TR909 CHH 2",
  "TR808 CHH 1",
  "TR808 CHH 2",
  "TR808 CHH 3",
  "TR606 CHH 1",
  "TR606 CHH 2",
  "TR606 DstCHH",
  "TR707 CHH",
  "CR78 CHH",
  "DR55 CHH 1",
  "Closed Hat",
  "Pop CHH",
  "Real CHH",
  "Bristol CHH",
  "DR550 CHH2",
  "Tight CHH",
  "Hip CHH",
  "Room CHH",
  "R8 Brush CHH",
  "Jungle Hat",
  "PHH MENU",
  "TR909 PHH 1",
  "TR909 PHH 2",
  "TR808 PHH 1",
  "TR808 PHH 2",
  "TR606 PHH 1",
  "TR606 PHH 2",
  "TR707 PHH",
  "HIP PHH",
  "Tight PHH",
  "Pedal Hat 1",
  "Real PHH",
  "Pedal Hat 2",
  "OHH MENU 1",
  "OHH MENU 2",
  "TR909 OHH 1",
  "TR909 OHH 2",
  "TR909 OHH 3",
  "TR909 DstOHH",
  "TR808 OHH 1",
  "TR808 OHH 2",
  "TR606 OHH",
  "TR606 DstOHH",
  "TR707 OHH",
  "CR78 OHH",
  "HIP OHH",
  "Pop Hat Open",
  "Open Hat",
  "Cym OHH",
  "DR550 OHH",
  "Funk OHH",
  "Real OHH",
  "R8 OHH",
  "Cymbal MENU",
  "TR606 Cym 1",
  "TR606 Cym 2",
  "TR909 Ride",
  "TR707 Ride",
  "Natural Ride",
  "Cup Cym",
  "TR909 Crash",
  "Natural Crash",
  "Jungle Crash",
  "Asian Gong",
  "CLAP MENU1",
  "CLAP MENU2",
  "TR909 Clap 1",
  "TR909 Clap 2",
  "TR808 Clap",
  "TR707 Clap",
  "Cheap Clap",
  "Funk Clap",
  "Little Clap",
  "Real Clap 1",
  "Real Clap 2",
  "Funky Clap",
  "Comp Clap",
  "Hip Clap",
  "Down Clap",
  "Group Clap",
  "Big Clap",
  "ClapTail",
  "Clap Snare 1",
  "Fuzzy Clap",
  "Snap",
  "Finger Snap",
  "SNR MENU 1",
  "SNR MENU 2",
  "SNR MENU 3",
  "SNR MENU 4",
  "SNR MENU 5",
  "SNR MENU 6",
  "TR909 Snr 1",
  "TR909 Snr 2",
  "TR909 Snr 3",
  "TR909 Snr 4",
  "TR909 Snr 5",
  "TR909 Snr 6",
  "TR909 Snr 7",
  "TR909 DstSnr",
  "TR808 Snr 1",
  "TR808 Snr 2",
  "TR808 Snr 3",
  "TR808 Snr 4",
  "TR808 Snr 5",
  "TR808 Snr 6",
  "TR808 Snr 7",
  "TR808 Snr 8",
  "TR808 Snr 9",
  "TR606 Snr 1",
  "TR606 Snr 2",
  "TR606 Snr 3",
  "DanceHall SD",
  "TR707 Snare",
  "CR78 Snare",
  "Clap Snare 2",
  "Jungle Tiny SD",
  "Jazz Snare",
  "Headz Snare",
  "Whack Snare",
  "Rap Snare",
  "Jungle Snr 1",
  "Antigua Snr",
  "Real Snr",
  "Tiny Snare 1",
  "Tiny Snare 2",
  "Break Snare 1",
  "Break Snare 2",
  "MC Snare",
  "East Snare",
  "Phat Snare",
  "Brush Slap 1",
  "Brush Slap 2",
  "Deep Snare",
  "Fat Snare",
  "Disco Snare",
  "Dj Snare",
  "Macho Snare",
  "Hash Snare",
  "Lo-Hard Snr",
  "Indus Snare",
  "Rage Snare",
  "TekRok Snare",
  "Big Trash SD",
  "Ragga Rim 2",
  "Gate Rim",
  "Sidestiker",
  "HipJazz Snr",
  "HH Soul Snr",
  "Cross Snr",
  "Jungle Rim 1",
  "Ragg Snr 2",
  "Upper Snare",
  "Lo-Fi Snare",
  "Ragga Tight SD",
  "Flange Snr",
  "Machine Snr",
  "Clap Snare 3",
  "Solid Snare",
  "Funk Clap 2",
  "Jungle Rim 2",
  "Jungle Rim 3",
  "Jungle Snr 2",
  "Urban Snare",
  "Urban RollSD",
  "R&B Snare",
  "R8 Brush Tap",
  "R8 BrshSwill",
  "R8 BrushRoll",
  "Sim Snare",
  "Electro Snr 1",
  "Electro Snr 2",
  "Synth Snr",
  "Roll Snare",
  "Kick MENU 1",
  "KICK MENU 2",
  "KICK MENU 3",
  "TR909 Kick 1",
  "TR909 Kick 2",
  "TR909 Kick 3",
  "TR909 Kick 4",
  "Plastic BD 1",
  "Plastic BD 2",
  "Plastic BD 3",
  "Plastic BD 4",
  "TR909 Kick 5",
  "TR808 Kick 1",
  "TR808 Kick 2",
  "TR808 Kick 3",
  "TR808 Kick 4",
  "TR808 Kick 5",
  "TR606 Kick",
  "TR606 Dst BD",
  "TR707 Kick 1",
  "TR707 Kick 2",
  "Toy Kick",
  "Analog Kick",
  "Boost Kick",
  "West Kick",
  "Jungle Kick 1",
  "Optic Kick",
  "Wet Kick",
  "Lo-Fi Kick",
  "Hazy Kick",
  "Hip Kick",
  "Video Kick",
  "Tight Kick",
  "Break Kick",
  "Turbo Kick",
  "Ele Kick",
  "Dance Kick 1",
  "Kick Ghost",
  "Lo-Fi Kick 2",
  "Jungle Kick 2",
  "TR909 Dst BD",
  "Amsterdam BD",
  "Gabba Kick",
  "Roll Kick"]

WAVES = (0..253).collect{ |n| '1-%d %s' % [n+1, WAVENAMES[n]] } + (0..250).collect{ |n| '2-%d %s ' % [n+1, WAVENAMES[n+254]] }

class WaveParameter < Qt::Object
  include ParameterRangeMod
  slots 'change(int)'
  def initialize(offset)
    super()
    @offset = offset
    @parameters = []
    add(ByteParameter.new('Wave group type', (0..0)))
    add(ByteParameter.new('Wave group ID', (1..2)))
    add(ByteParameter.new('Wave number (high nibble)', (0..15)))
    add(ByteParameter.new('Wave number (low nibble)', (0..15)))
  end
  def write(offset, value)
    super
    if offset == @offset+3
      if @parameters[1].read == 2
        num = 254
      else
        num = 0
      end
      num += @parameters[2].read << 4
      num += @parameters[3].read
      if @list
        @list.block_signals(true)
        @list.set_selected(num, true)
        @list.block_signals(false)
        @list.top_item = num - 4
      end
    end
  end
  def build_widgets(parent)
    @label = Qt::Label.new('Waveform', parent)
    box = Qt::HBox.new(parent)
    @list = Qt::ListBox.new(box)
    @list.insert_string_list(WAVES)
    connect(@list, SIGNAL('highlighted(int)'), self, SLOT('change(int)'))
  end
  def change(wave)
    if wave > 253
      gid = 2
      num = wave - 254
    else
      gid = 1
      num = wave
    end
    high = num >> 4
    low = num & 0xf
    @parameters[0].write(0)
    @parameters[1].write(gid)
    @parameters[2].write(high)
    @parameters[3].write(low)
    str = @parameters.collect{ |p| p.read }.pack('CCCC')
    send_sysex(data_set(@offset, str))
    @parameters[0].auto_trigger
  end
end

class PatchName < Qt::Object
  include ParameterRangeMod
  slots 'change()'
  def initialize(offset)
    super()
    @offset = offset
    @parameters = []
    12.times do |n|
      add(ByteParameter.new('Patch name %d' % (n + 1), (32..125)))
    end
  end
  def write(offset, value)
    super
    if offset == @offset+11
      if @lineedit
        @lineedit.set_text(@parameters.collect{ |p| p.read.chr }.join.strip)
      end
    end
  end
  def build_widgets(parent)
    @label = Qt::Label.new('Name', parent)
    @lineedit = Qt::LineEdit.new(parent)
    @lineedit.max_length = 12
    connect(@lineedit, SIGNAL('textChanged(const QString &)'), self, SLOT('change()'))
  end
  def change()
    send_sysex(data_set(@offset, "%-12s" % (@lineedit.text[0...12])))
  end
end

class ParameterSet
  attr_accessor :parent
  attr_reader :name
  attr_accessor :trigger_channel
  attr_accessor :trigger_note
  def initialize(offset = 0, name = nil)
    @offset = offset
    @name = name
    @ranges = []
    yield self
  end
  def dump(indent = 0)
    if @name
      print "  " * indent
      print "%s\n" % @name
    end
    @ranges.each do |r, o|
      print "  " * (indent+1)
      print "(%8x...%8x)\n" % [r.first, r.last]
      o.dump(indent + 2)
    end
  end
  def subsets
    @ranges.collect{ |r, o| o }
  end
  def build_widgets(parent)
    g = Qt::GroupBox.new(2, Qt::GroupBox::Horizontal, parent)
    if @name
      g.title = @name
    end
    build_child_widgets(g)
  end
  def build_child_widgets(parent)
    @ranges.each do |r, o|
      o.build_widgets(parent)
    end
  end
  def add_range(offset, klass = ParameterRange)
    o = offset + @offset
    range = klass.new(o)
    range.parent = self
    yield range
    @ranges.push([(o...o + range.length), range])
  end
  def end
    @ranges.collect{ |r| r.first.last }.max
  end
  def add_group(offset, name, &block)
    o = offset + @offset
    group = ParameterSet.new(o, name, &block)
    group.parent = self
    @ranges.push([(o...group.end), group])
  end
  def load
    if self.end - @offset > 127
      @ranges.each do |r, o|
        o.load
      end
    else
      send_sysex(data_request(@offset, self.end - @offset))
    end
  end
  def write(offset, value)
    @ranges.each do |r|
      if r.first.member?(offset)
        r.last.write(offset, value)
        return
      end
    end
    #print "Unmapped parameter: %8x\n" % offset
  end
  def read(offset)
    @ranges.each do |r|
      if r.first.member?(offset)
        r.last.read(offset)
        return
      end
    end
  end
  def auto_trigger
    ref = self
    loop do
      break if ref.respond_to?(:trigger_channel) and ref.trigger_channel
      if ref.respond_to?(:parent)
        ref = ref.parent
      else
        return
      end
    end
    $note_trigger.auto_trigger(ref.trigger_channel, ref.trigger_note)
  end
end

######################################################################

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

$pages = []

$params = ParameterSet.new(0, 'Parameter map') do |p|
  p.add_group(0, 'System') do |g0|
    $pages.push(g0)
    g0.add_group(0, 'Common') do |g1|
      g1.add_range(6) do |r|
        r.add(ByteParameter.new('Master tune', (0..126)))
        r.add(ByteParameter.new('Scale tune switch', (0..1), %w[Off On]))
        r.add(ByteParameter.new('MFX switch', (0..1), %w[Off On]))
        r.add(ByteParameter.new('Delay switch', (0..1), %w[Off On]))
        r.add(ByteParameter.new('Reverb switch', (0..1), %w[Off On]))
        r.add(ByteParameter.new('Patch remain', (0..1), %w[Off On]))
      end
      g1.add_range(0x14) do |r|
        r.add(ByteParameter.new('Receive program change switch', (0..1), %w[Off On]))
        r.add(ByteParameter.new('Receive bank select switch', (0..1), %w[Off On]))
      end
      g1.add_range(0x28) do |r|
        r.add(ByteParameter.new('Transmit program change switch', (0..1), %w[Off On]))
        r.add(ByteParameter.new('Transmit bank select switch', (0..1), %w[Off On]))
      end
    end
    7.times do |n0|
      g0.add_group(0x1000 + 0x100 * n0, 'Part %d scale tune' % (n0 + 1)) do |g1|
        g1.add_range(0) do |r|
          %w[C C# D D# E F F# G G# A A# B].each do |note|
            r.add(ByteParameter.new('Scale tune for ' + note, (0..127)))
          end
        end
      end
    end
  end
  p.add_group(0x1000000, 'Part info') do |g0|
    $pages.push(g0)
    g0.add_group(0, 'Common') do |g1|
      g1.add_range(0xd) do |r|
        r.add(ByteParameter.new('MFX type', (0..24), MFX_TYPE))
        11.times do |n0|
          r.add(ByteParameter.new('MFX control %d' % (n0 + 1), (0..127)))
        end
      end
      g1.add_range(0x1c) do |r|
        r.add(ByteParameter.new('MFX delay send level', (0..127)))
        r.add(ByteParameter.new('MFX reverb send level', (0..127)))
      end
      g1.add_range(0x22) do |r|
        r.add(ByteParameter.new('Delay level', (0..127)))
        r.add(ByteParameter.new('Delay type', (0..1), %w[Short Long]))
        r.add(ByteParameter.new('Delay HF damp', (0..17), HF_DAMP))
        r.add(ByteParameter.new('Delay time', (0..120)))
        r.add(ByteParameter.new('Delay feedback level', (0..98)))
        r.add(ByteParameter.new('Delay output assign', (0..2), %w[Line Reverb Line+Reverb]))
        r.add(ByteParameter.new('Reverb type', (0..5), %w[Room1 Room2 Stage1 Stage2 Hall1 Hall2]))
        r.add(ByteParameter.new('Reverb level', (0..127)))
        r.add(ByteParameter.new('Reverb time', (0..127)))
        r.add(ByteParameter.new('Reverb HF damp', (0..17), HF_DAMP))
      end
      g1.add_range(0x30) do |r|
        7.times do |n0|
          r.add(ByteParameter.new('Voice reserve %d' % (n0 + 1), (0..64)))
        end
      end
      g1.add_range(0x39) do |r|
        r.add(ByteParameter.new('Voice reserve R', (0..64)))
      end
    end
    [0,1,2,3,4,5,6,9].each do |n0|
      if n0 < 9
        name = (n0 + 1).to_s
      else
        name = 'R'
      end
      g0.add_group(0x1000 + 0x100 * n0, 'Part ' + name) do |g1|
        g1.add_range(0) do |r|
          r.add(ByteParameter.new('Receive switch', (0..1)))
        end
        g1.add_range(2) do |r|
          r.add(ByteParameter.new('Patch group type', (0..3)))
          r.add(ByteParameter.new('Patch group ID', (1..9)))
          r.add(ByteParameter.new('Patch number (high nibble)', (0..15)))
          r.add(ByteParameter.new('Patch number (low nibble)', (0..15)))
          r.add(ByteParameter.new('Part level', (0..127)))
          r.add(ByteParameter.new('Part pan', (0..127)))
          r.add(ByteParameter.new('Part key shift', (0..96)))
          r.add(ByteParameter.new('Part fine tune', (0..100)))
          r.add(ByteParameter.new('MFX switch', (0..4), %w[Off On Reserved Reserved Rythm]))
        end
        g1.add_range(0xc) do |r|
          r.add(ByteParameter.new('Delay send level', (0..127)))
          r.add(ByteParameter.new('Reverb send level', (0..127)))
        end
      end
    end
  end
  p.add_group(0x2000000, 'Patches') do |g0|
    7.times do |n0|
      g0.add_group(0x10000 * n0, 'Patch %d' % (n0 + 1)) do |g1|
        $pages.push(g1)
        g1.trigger_channel = n0
        g1.add_group(0, 'Common') do |g2|
          g2.add_range(0, PatchName) do |r|
          end
          g2.add_range(0x31) do |r|
            r.add(ByteParameter.new('Bend range up', (0..12)))
            r.add(ByteParameter.new('Bend range down', (0..48)))
            r.add(ByteParameter.new('Solo switch', (0..1), %w[Off On]))
            r.add(ByteParameter.new('Solo legato switch', (0..1), %w[Off On]))
            r.add(ByteParameter.new('Portamento switch', (0..1), %w[Off On]))
            r.add(ByteParameter.new('Portamento mode', (0..1), %w[Normal Legato]))
            r.add(ByteParameter.new('Portamento type', (0..1), %w[Rate Time]))
            r.add(ByteParameter.new('Portamento start', (0..1), %w[Pitch Note]))
            r.add(ByteParameter.new('Portamento time', (0..127)))
          end
          g2.add_range(0x40) do |r|
            r.add(ByteParameter.new('Velocity range switch', (0..1), %w[Off On]))
          end
          g2.add_range(0x42) do |r|
            r.add(ByteParameter.new('Stretch tune depth', (0..3), %w[Off 1 2 3]))
            r.add(ByteParameter.new('Voice priority', (0..1), %w[Last Loudest]))
            r.add(ByteParameter.new('Structure type 1/2', (0..9)))
            r.add(ByteParameter.new('Booster 1/2', (0..3), %w[0 +6 +12 +18]))
            r.add(ByteParameter.new('Structure type 3/4', (0..9)))
            r.add(ByteParameter.new('Booster 3/4', (0..3), %w[0 +6 +12 +18]))
          end
        end
        4.times do |n1|
          g1.add_group(0x1000 + 0x200 * n1, 'Tone %d' % (n1 + 1)) do |g2|
            g2.add_range(0) do |r|
              r.add(ByteParameter.new('Tone switch', (0..1), %w[Off On]))
            end
            g2.add_range(1, WaveParameter) do |r|
            end
            g2.add_range(5) do |r|
              r.add(ByteParameter.new('Wave gain', (0..3), WAVE_GAIN))
              r.add(ByteParameter.new('FXM switch', (0..1), %w[Off On]))
              r.add(ByteParameter.new('FXM color', (0..3)))
              r.add(ByteParameter.new('FXM depth', (0..15)))
            end
            g2.add_range(0xb) do |r|
              r.add(ByteParameter.new('Velocity crossfade', (0..127)))
              r.add(ByteParameter.new('Velocity range lower', (1..127)))
              r.add(ByteParameter.new('Velocity range upper', (1..127)))
              r.add(ByteParameter.new('Keyboard range lower', (0..127)))
              r.add(ByteParameter.new('Keyboard range upper', (0..127)))
            end
            g2.add_range(0x15) do |r|
              ['Modulation', 'Pitch bend', 'Aftertouch'].each do |modtype|
                4.times do |modn|
                  r.add(ByteParameter.new('%s %d destination' % [modtype, (modn+1)], (0..15), %w[Off PCH CUT RES LEV PAN L1P L2P L1F L2F L1A L2A PL1 PL2 L1R L2R]))
                  r.add(ByteParameter.new('%s %d depth' % [modtype, (modn+1)], (0..127)))
                end
              end
              2.times do |lfon|
                r.add(ByteParameter.new('LFO%d waveform' % (lfon+1), (0..7), %w[TRI SIN SAW SQR TRP S&H RND CHS]))
                r.add(ByteParameter.new('LFO%d key sync' % (lfon+1), (0..1)))
                r.add(ByteParameter.new('LFO%d rate' % (lfon+1), (0..127)))
                r.add(ByteParameter.new('LFO%d offset' % (lfon+1), (0..4), %w[-100 -50 0 +50 +100]))
                r.add(ByteParameter.new('LFO%d delay time' % (lfon+1), (0..127)))
                r.add(ByteParameter.new('LFO%d fade mode' % (lfon+1), (0..3), %w[ON-IN ON-OUT OFF-IN OFF-OUT]))
                r.add(ByteParameter.new('LFO%d fade time' % (lfon+1), (0..127)))
                r.add(ByteParameter.new('LFO%d tempo sync' % (lfon+1), (0..1), %w[Off On]))
              end
              r.add(ByteParameter.new('Coarse tune', (0..96)))
              r.add(ByteParameter.new('Fine tune', (0..100)))
              r.add(ByteParameter.new('Random pitch depth', (0..30), RANDOM_PITCH_DEPTH))
              r.add(ByteParameter.new('Pitch key follow', (0..15), KEYFOLLOW))
              r.add(ByteParameter.new('Pitch envelope depth', (0..24)))
              r.add(ByteParameter.new('Pitch envelope velocity sens', (0..125)))
              r.add(ByteParameter.new('Pitch envelope velocity time 1', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Pitch envelope velocity time 4', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Pitch envelope time key follow', (0..14), KEYFOLLOW2))
              4.times do |n2|
                r.add(ByteParameter.new('Pitch envelope time %d' % n2, (0..127)))
              end
              4.times do |n2|
                r.add(ByteParameter.new('Pitch envelope level %d' % n2, (0..126)))
              end
              r.add(ByteParameter.new('Pitch LFO1 depth', (0..126)))
              r.add(ByteParameter.new('Pitch LFO2 depth', (0..126)))

              r.add(ByteParameter.new('Filter type', (0..4), FILTER_TYPE))
              r.add(ByteParameter.new('Cutoff frequency', (0..127)))
              r.add(ByteParameter.new('Cutoff key follow', (0..15), KEYFOLLOW))
              r.add(ByteParameter.new('Resonance', (0..127)))
              r.add(ByteParameter.new('Resonance velocity sens', (0..125)))
              r.add(ByteParameter.new('Filter envelope depth', (0..126)))
              r.add(ByteParameter.new('Filter envelope velocity curve', (0..6)))
              r.add(ByteParameter.new('Filter envelope velocity sens', (0..125)))
              r.add(ByteParameter.new('Filter envelope velocity time 1', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Filter envelope velocity time 4', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Filter envelope time key follow', (0..14), KEYFOLLOW2))
              4.times do |n2|
                r.add(ByteParameter.new('Filter envelope time %d' % n2, (0..127)))
              end
              4.times do |n2|
                r.add(ByteParameter.new('Filter envelope level %d' % n2, (0..127)))
              end
              r.add(ByteParameter.new('Filter LFO1 depth', (0..126)))
              r.add(ByteParameter.new('Filter LFO2 depth', (0..126)))

              r.add(ByteParameter.new('Tone level', (0..127)))
              r.add(ByteParameter.new('Bias direction', (0..3), %w[Lower Upper Low&Up All]))
              r.add(ByteParameter.new('Bias point', (0..127)))
              r.add(ByteParameter.new('Bias level', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Amp envelope velocity curve', (0..6)))
              r.add(ByteParameter.new('Amp envelope velocity sens', (0..125)))
              r.add(ByteParameter.new('Amp envelope velocity time 1', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Amp envelope velocity time 4', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Amp envelope time key follow', (0..14), KEYFOLLOW2))
              4.times do |n2|
                r.add(ByteParameter.new('Amp envelope time %d' % n2, (0..127)))
              end
              3.times do |n2|
                r.add(ByteParameter.new('Amp envelope level %d' % n2, (0..127)))
              end
              r.add(ByteParameter.new('Amp LFO1 depth', (0..126)))
              r.add(ByteParameter.new('Amp LFO2 depth', (0..126)))
              r.add(ByteParameter.new('Tone pan', (0..127)))
              r.add(ByteParameter.new('Pan key follow', (0..14), KEYFOLLOW2))
              r.add(ByteParameter.new('Random pan', (0..63)))
              r.add(ByteParameter.new('Alternate pan depth', (1..127)))
              r.add(ByteParameter.new('Pan LFO1 depth', (0..126)))
              r.add(ByteParameter.new('Pan LFO2 depth', (0..126)))
            end
          end
        end
      end
    end
  end
  p.add_group(0x2090000, 'Rythm Set') do |g0|
    $pages.push(g0)
    g0.add_group(0, 'Common') do |g1|
      g1.add_range(0, PatchName) do |r|
      end
    end
    (35..98).each do |n0|
      g0.add_group(0x100 * n0, 'Note %d' % (n0)) do |g1|
        g1.trigger_channel = 9
        g1.trigger_note = n0
        g1.add_range(0) do |r|
          r.add(ByteParameter.new('Tone switch', (0..1), %w[Off On]))
        end
        g1.add_range(1, WaveParameter) do |r|
        end
        g1.add_range(5) do |r|
          r.add(ByteParameter.new('Wave gain', (0..3), WAVE_GAIN))
          r.add(ByteParameter.new('Bend range', (0..12)))
          r.add(ByteParameter.new('Mute group', (0..32), ['Off'] + (1..31).collect{|n| n.to_s}))
          r.add(ByteParameter.new('Envelope mode', (0..1), ['No sustain', 'Sustain']))
        end
        g1.add_range(0xc) do |r|
          r.add(ByteParameter.new('Coarse tune', (0..96)))
          r.add(ByteParameter.new('Fine tune', (0..100)))
          r.add(ByteParameter.new('Random pitch depth', (0..30), RANDOM_PITCH_DEPTH))
          r.add(ByteParameter.new('Pitch envelope depth', (0..24)))
          r.add(ByteParameter.new('Pitch envelope velocity sens', (0..125)))
          r.add(ByteParameter.new('Pitch envelope velocity time', (0..14), KEYFOLLOW2))
          4.times do |n2|
            r.add(ByteParameter.new('Pitch envelope time %d' % n2, (0..127)))
          end
          4.times do |n2|
            r.add(ByteParameter.new('Pitch envelope level %d' % n2, (0..126)))
          end
          r.add(ByteParameter.new('Filter type', (0..4), FILTER_TYPE))
          r.add(ByteParameter.new('Cutoff frequency', (0..127)))
          r.add(ByteParameter.new('Resonance', (0..127)))
          r.add(ByteParameter.new('Resonance velocity sens', (0..125)))
          r.add(ByteParameter.new('Filter envelope depth', (0..126)))
          r.add(ByteParameter.new('Filter envelope velocity sens', (0..125)))
          r.add(ByteParameter.new('Filter envelope velocity time', (0..14), KEYFOLLOW2))
          4.times do |n2|
            r.add(ByteParameter.new('Filter envelope time %d' % n2, (0..127)))
          end
          4.times do |n2|
            r.add(ByteParameter.new('Filter envelope level %d' % n2, (0..127)))
          end
          r.add(ByteParameter.new('Tone level', (0..127)))
          r.add(ByteParameter.new('Amp envelope velocity sens', (0..125)))
          r.add(ByteParameter.new('Amp envelope velocity time', (0..14), KEYFOLLOW2))
          4.times do |n2|
            r.add(ByteParameter.new('Amp envelope time %d' % n2, (0..127)))
          end
          3.times do |n2|
            r.add(ByteParameter.new('Amp envelope level %d' % n2, (0..127)))
          end
          r.add(ByteParameter.new('Tone pan', (0..127)))
          r.add(ByteParameter.new('Random pan', (0..63)))
          r.add(ByteParameter.new('Alternate pan depth', (1..127)))
          r.add(ByteParameter.new('MFX switch', (0..1), %w[Off On]))
        end
        g1.add_range(0x38) do |r|
          r.add(ByteParameter.new('Delay send level', (0..127)))
          r.add(ByteParameter.new('Reverb send level', (0..127)))
        end
      end
    end
  end
end

######################################################################

def checksum(data)
  sum = 0
  data.each_byte { |b| sum += b }
  return 128 - sum % 128
end

def data_request(addr, size)
  head = "\xf0\x41" + $id.chr + "\x00\x0b\x11"
  msg = [addr, size].pack('NN')
  sum = 0
  msg.each_byte { |b| sum += b }
  tail = [128 - sum % 128, 0xf7].pack('CC')
  return head + msg + tail
end

def data_set(addr, data)
  head = "\xf0\x41" + $id.chr + "\x00\x0b\x12"
  msg = [addr].pack('N') + data
  tail = [checksum(msg), 0xf7].pack('CC')
  return head + msg + tail
end

def parse_data_set(sysexdata)
  head = sysexdata[0...6]
  addr = sysexdata[6...10]
  data = sysexdata[10...-2]
  sum = sysexdata[-2]
  return false if head != "\xf0\x41" + $id.chr + "\x00\x0b\x12"
  if sum != checksum(addr+data)
    print "Wrong checksum for data_set!\n"
  end
  numaddr = addr.unpack('N')[0]
  data.each_byte do |b|
    $params.write(numaddr, b)
    numaddr += 1
  end
  return true
end

######################################################################

def send_sysex(data)
  print 'Send:'
  hexdump(data)
  ev = Snd::Seq::Event.new
  ev.source = $port
  ev.set_subs
  ev.set_direct
  ev.set_sysex(data)
  $seq.event_output(ev)
  $seq.drain_output
end

def identity_request!
  send_sysex("\xf0\x7e\x7f\x06\x01\xf7")
end

def identity_response?(ev)
  return false if ev.type != Snd::Seq::EVENT_SYSEX
  return /\x7e.\x06\x02\x41\x0b\x01\x03\x00\x00\x03\x00\x00\xf7/.match(ev.get_variable)
end

def hexdump(str)
  str.each_byte do |byte|
    print " %02x" % byte
  end
  print "\n"
end

######################################################################

class NoteTrigger < Qt::Object
  slots 'untrigger()', 'note=(int)', 'velocity=(int)', 'enabled=(bool)'
  attr_accessor :note, :velocity, :enabled
  def initialize
    super()
    @timer = Qt::Timer.new
    connect(@timer, SIGNAL('timeout()'), self, SLOT('untrigger()'))
    @triggered = false
    @note = 57
    @velocity = 100
    @enabled = true
  end
  def auto_trigger(channel, note)
    if @enabled
      trigger(channel, note || @note, @velocity)
    end
  end
  def trigger(channel, note, velocity)
    if @triggered
      untrigger
    end
    @last_note = [channel, note]
    @triggered = true
    ev = Snd::Seq::Event.new
    ev.source = $port
    ev.set_subs
    ev.set_direct
    ev.set_noteon(channel, note, velocity)
    $seq.event_output(ev)
    $seq.drain_output
    @timer.start(500, true)
  end
  def untrigger
    @timer.stop
    @triggered = false

    ev = Snd::Seq::Event.new
    ev.source = $port
    ev.set_subs
    ev.set_direct
    ev.set_noteoff(@last_note[0], @last_note[1], 0)
    $seq.event_output(ev)
    $seq.drain_output
  end
end
class MainWindow < KDE::MainWindow
  slots 'idle()', 'load_page(QWidget *)', 'reload()', 'snapshot()'

  def initialize(name)
    super(nil, name)
    setCaption(name)

    @timer = Qt::Timer.new
    connect(@timer, SIGNAL('timeout()'), self, SLOT('idle()'))
    @timer.start(0)
    KDE::StdAction.quit(self, SLOT('close()'), actionCollection())
    KDE::Action.new(i18n('Reload parameters'), 'reload', KDE::Shortcut.new(0), self, SLOT('reload()'), actionCollection(), 'reload')
    KDE::Action.new(i18n('Send snapshot of parameters'), 'filesave', KDE::Shortcut.new(0), self, SLOT('snapshot()'), actionCollection(), 'snapshot')
    @checkbox = KDE::ToggleAction.new(i18n('Auto trigger note'), 'player_play', KDE::Shortcut.new(0), self, SLOT('reload()'), actionCollection(), 'autotrigger')
    @trigger = Qt::HBox.new(nil)
    @trigger.set_spacing(5)
    Qt::Label.new('Auto trigger note', @trigger)
    #@checkbox = Qt::CheckBox.new(@trigger)
    @checkbox.set_checked($note_trigger.enabled)
    @notebox = Qt::SpinBox.new(1, 128, 1, @trigger)
    @notebox.value = $note_trigger.note
    Qt::Label.new('Velocity', @trigger)
    @velocitybox = Qt::SpinBox.new(1, 127, 1, @trigger)
    @velocitybox.value = $note_trigger.velocity
    connect(@checkbox, SIGNAL('toggled(bool)'), $note_trigger, SLOT('enabled=(bool)'))
    connect(@notebox, SIGNAL('valueChanged(int)'), $note_trigger, SLOT('note=(int)'))
    connect(@velocitybox, SIGNAL('valueChanged(int)'), $note_trigger, SLOT('velocity=(int)'))
    KDE::WidgetAction.new(@trigger, 'Gurk', KDE::Shortcut.new(0), self, SLOT('idle()'), actionCollection(), 'note_trigger')

    #createGUI
    createGUI(Dir.getwd + "/rmc505ui.rc")

    @janus = KDE::JanusWidget.new(self, 'j', KDE::JanusWidget::TreeList)
    connect(@janus, SIGNAL('aboutToShowPage(QWidget *)'), self, SLOT('load_page(QWidget *)'))

    pixmaps = {}
    %w[patch drum].each do |n|
      pixmaps[n] = Qt::Pixmap.new(n + '.png')
    end

    @frame_params = {}
    $pages.each do |patch|
      patch.subsets.each do |subset|
        if subset.name == 'Common'
          frame = @janus.add_page([patch.name], nil)
          pixmap = (case patch.name
                    when /^Patch/ then 'patch'
                    when /^Rythm/ then 'drum'
                    end)
          @janus.set_folder_icon([patch.name], pixmaps[pixmap]) if pixmap
        else
          frame = @janus.add_page([patch.name, subset.name], nil)
        end
        grid = Qt::GridLayout.new(frame, 1, 1)
        scroll = Qt::ScrollView.new(frame)
        grid.add_widget(scroll, 0, 0)
        vbox = Qt::VBox.new(scroll.viewport)
        scroll.add_child(vbox)
        scroll.resize_policy = Qt::ScrollView::AutoOneFit
        scroll.set_margins(5,5,5,5)
        @frame_params[frame.win_id] = [subset, vbox, false]
      end
    end
    reload()
    set_central_widget(@janus)
  end

  def load_page(widget)
    subset, vbox, widgets_built = @frame_params[widget.win_id]
    subset.load
    if not widgets_built
      @frame_params[widget.win_id][2] = true
      subset.build_widgets(vbox)
    end
    subset.auto_trigger
  end

  def reload()
    load_page(@janus.page_widget(@janus.active_page_index))
  end

  def idle
    event = nil
    while (event = $seq.event_input) do
      if event.type != Snd::Seq::EVENT_CLOCK
        if event.type == Snd::Seq::EVENT_SYSEX
          sysexdata = event.get_variable
          if parse_data_set(event.get_variable)
            print "Recieved %d bytes of parameters\n" % (sysexdata.length - 12)
          else
            print 'Recv:'
            hexdump(sysexdata)
            print "(~%d bytes of parameters)\n" % (sysexdata.length - 12)
          end
        else
          print "MIDI! %d \n" % event.type
        end
      end
    end
    # Sometimes, this timer just stops working. This seems to fix it:
    @timer.start(0)
  end

end

######################################################################

about = KDE::AboutData.new('rmc505',
                           'Rmc505',
                           '0.0.1',
                           'A Roland MC505/D2 patch editor',
                           KDE::AboutData::License_GPL,
                           '(C) 2006 Nicklas Lindgren')
about.add_author('Nicklas Lindgren',
                 'Programmer',
                 'nili@lysator.liu.se')

KDE::CmdLineArgs.init(ARGV, about)
a = KDE::Application.new()

# $params.dump

$seq = Snd::Seq.open
$seq.client_name = 'rmc505'
$port = $seq.create_simple_port('Data transfer',
                                Snd::Seq::PORT_CAP_READ | Snd::Seq::PORT_CAP_SUBS_READ |
                                  Snd::Seq::PORT_CAP_WRITE | Snd::Seq::PORT_CAP_SUBS_WRITE,
                                Snd::Seq::PORT_TYPE_MIDI_GENERIC)

$seq.connect_to($port, 20, 0)
$seq.connect_from($port, 20, 0)

identity_request!
while (event = $seq.event_input) do
  if event.type == Snd::Seq::EVENT_SYSEX
    if identity_response?(event)
      $id = event.get_variable[2]
      print "Response from D2 with id %d\n" % $id
      if $id != 16
        print "This won't work right now."
      end
      break
    end
  end
end
$seq.nonblock = true

$note_trigger = NoteTrigger.new
# $params.load

window = MainWindow.new('Rmc505')
window.resize(640, 480)

a.main_widget = window
window.show

a.exec
