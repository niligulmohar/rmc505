module RolandSysex
  MANUFACTURER_ID = 0x41
  def manufacturer_id() 0x41 end
  def self.checksum(data)
    sum = 0
    data.each_byte { |b| sum += b }
    return 128 - sum % 128
  end
  module ConnectionMethods
    def specific_sysex_match?(event)
      m = @device_class.manufacturer_id
      f = @device_class.family_code[0..0]
      event.variable_data =~ /^\xf0#{m.chr}#{@sysex_channel.chr}\x00#{f}./
    end
    def read_data_request(start, length)
      head = "\xf0\x41#{@sysex_channel.chr}\x00\x0b\x11"
      msg = [start, length].pack('NN')
      tail = [RolandSysex.checksum(msg), 0xf7].pack('CC')
      return head + msg + tail
    end
    def write_data_request(start, data)
      head = "\xf0\x41#{@sysex_channel.chr}\x00\x0b\x12"
      msg = [start].pack('N') + data
      tail = [RolandSysex.checksum(msg), 0xf7].pack('CC')
      return head + msg + tail
    end
    def write_data_request?(sysex_data)
      sysex_data =~ /^\xf0....\x12/
    end
    def parse_write_data_request(sysex_data)
      match = sysex_data.match(/^\xf0\x41.\x00.\x12(....)(.+)(.)\xf7$/)
      fail if match.nil?
      channel_s addr_s, data, checksum_s = match[1..3]
      addr = addr_s.unpack('N')
      checksum = checksum_s[0]
      if checksum != RolandSysex.checksum(addr_s + data)
        $logger.warn(log_format('Wrong checksum in write data request!'))
        addr = 0
        data = ''
      end
      $logger.debug(log_format(sysex_data))
      return [addr, data]
    end
    alias_method :parse_read_data_response, :parse_write_data_request
    alias_method :read_data_response?, :write_data_request?
  end
end

module AlphaJunoSysex
  include RolandSysex
  def sysex_match_channel(event)
    m = RolandSysex::MANUFACTURER_ID
    match = event.variable_data.match(/^\xf0#{m.chr}[\x35\x36](.)\x23\x20\x01/)
    return (if match
              match[1][0]
            else
              nil
            end)
  end
  module ConnectionMethods
    def specific_sysex_match?(event)
      m = RolandSysex::MANUFACTURER_ID
      event.variable_data =~ /^\xf0#{m.chr}[\x35\x36]#{@sysex_channel.chr}\x23\x20\x01/
    end
    def write_data_request(start, data)
      if data.length == 1
        #IPR
      elsif start == 0 and data.length == 46
        #APR
      else
        fail "Write request won't fit either an APR or an IPR"
      end
      
    end
    def write_data_request?(sysex_data)
      true
    end
    def parse_write_data_request(sysex_data)
      case sysex_data[2]
      when 0x35
        return [0, sysex_data[7...(7+46)]]
      when 0x36
        return [sysex_data[7], sysex_data[8..8]]
      else
        fail
      end
    end
    alias_method :parse_read_data_response, :parse_write_data_request
    alias_method :read_data_response?, :write_data_request?
  end
end

######################################################################
#  ____   ____ ____         _    _____  ___
# |  _ \ / ___|  _ \       / \  |___ / / _ \
# | |_) | |   | |_) |____ / _ \   |_ \| | | |
# |  __/| |___|  _ <_____/ ___ \ ___) | |_| |
# |_|    \____|_| \_\   /_/   \_\____/ \___/

DeviceClass.new('PCR-A30') do |c|
  c.icon = :patch
  c.priority = 2
  c.extend(RolandSysex)
  c.connection_methods << RolandSysex::ConnectionMethods
  c.connection_methods << BulkParameters
  c.family_code = "\x62\x01"
  c.model_number = "\x00\x00"
  c.version_number = "\x01\x01\x00\x00"

  c.parameter_map do |p|
    p.delay = 0.5
    (1..0xf).each do |n|
      p.offset(0, 'Memory set %X' % n) do |m|
        m.list_entry = true
        m.delay = 0.04
        %w[R1 R2 R3 R4 R5 R6 R7 R8
           S1 S2 S3 S4 S5 S6 S7 S8
           B1 B2 B3 B4 B5 B6
           L1 L2 L3
           P1 P2].each_with_index do |c, n|
          m.offset(n * 0x100, c) do |cg|
            cg.list_entry = true
            cg.offset(0, 'Unknown') do |r|
              r.page_entry = true
              128.times do
                r.param('Unknown', (0..127))
              end
            end
          end
        end
      end
    end
  end
end

######################################################################
#        _       _                 _
#   __ _| |_ __ | |__   __ _      | |_   _ _ __   ___
#  / _` | | '_ \| '_ \ / _` |  _  | | | | | '_ \ / _ \
# | (_| | | |_) | | | | (_| | | |_| | |_| | | | | (_) |
#  \__,_|_| .__/|_| |_|\__,_|  \___/ \__,_|_| |_|\___/
#         |_|

class AlphaJunoToneLineEdit < Qt::LineEdit
  slots 'set()'
  def initialize(tone_name, parent)
    super(parent)
    @tone_name = tone_name
    connect(self, SIGNAL('textChanged(const QString &)'),
            self, SLOT('set()'))
    @tone_name.elements.each{ |e| e.add_observer(self) }
    update
  end
  def update
    return if @disable_update
    set_text(@tone_name.map_parent.value(@tone_name))
  end
  def set
    @disable_update = true
    @tone_name.update_elements_and_notify do |parameters|
      padded_text = '%-12s' % text
      padded_text.split('').each_with_index do |char, index|
        #parameters[index].set(char[0])
      end
    end
    @disable_update = false
  end
end

class AlphaJunoToneName < ParameterMap
  CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -"
  def initialize(*args)
    super
    10.times do |n|
      param("Tone name #{n+1}", (0..63))
    end
  end
  def value(data)
    data.elements.collect{ |p| CHARACTERS[p.value..p.value] }.join.strip
  end
  def special_widget?
    true
  end
  def label
    'Tone name'
  end
  def widget(data, parent)
    @lineedit = AlphaJunoToneLineEdit.new(data, parent)
    @lineedit.max_length = 10
    return @lineedit
  end
end

DeviceClass.new('Alpha Juno') do |c|
  c.icon = :patch
  c.priority = 1
  c.extend(AlphaJunoSysex)
  c.connection_methods << AlphaJunoSysex::ConnectionMethods
  c.connection_methods << PushedParameters
  c.parameter_map do |p|
    p.offset(0, 'Tone') do |g0|
      g0.list_entry = :tone
      g0.offset(0, 'Parameters') do |g|
        g.page_entry = true
        g.param('DCO Env Mode', (0..3), ([ 'Env normal',
                                           'Env inverted',
                                           'Env normal with velocity',
                                           'Env inverted with velocity' ]))
        g.param('VCF Env Mode', (0..3), ([ 'Env normal',
                                           'Env inverted',
                                           'Env normal with velocity',
                                           'Velocity' ]))
        g.param('VCA Env Mode', (0..3), ([ 'Env',
                                           'Gate',
                                           'Env with velocity',
                                           'Gate with velocity' ]))
        g.param('DCO Waveform Pulse', (0..3))
        g.param('DCO Waveform Sawtooth', (0..5))
        g.param('DCO Waveform Sub', (0..5))
        g.param('DCO Range', (0..3), %w[4' 8' 16' 32'])
        g.param('DCO Sub Level', (0..3))
        g.param('DCO Noise Level', (0..3))
        g.param('HPF Cutoff Freq', (0..3))
        g.param('Chorus', (0..1), %w[Off On])
        g.param('DCO LFO Mod Depth', (0..127))
        g.param('DCO Env Mod Depth', (0..127))
        g.param('DCO After Depth', (0..127))
        g.param('DCO PW/PWM Depth', (0..127))
        g.param('DCO PWM Rate', (0..127))
        g.param('VCF Cutoff Freq', (0..127))
        g.param('VCF Resonance', (0..127))
        g.param('VCF LFO Mod Depth', (0..127))
        g.param('VCF Env Mod Depth', (0..127))
        g.param('VCF Key Follow', (0..127))
        g.param('VCF After Depth', (0..127))
        g.param('VCA Level', (0..127))
        g.param('VCA After Depth', (0..127))
        g.param('LFO Rate', (0..127))
        g.param('LFO Delay Time', (0..127))
        (1..4).each do |n|
          g.param("Env T#{n}", (0..127))
          g.param("Env L#{n}", (0..127)) unless n == 4
        end
        g.param('Env Key Follow', (0..127))
        g.param('Chorus Rate', (0..127))
        g.param('Bender Range', (0..12))
        g.add_submap_of_class(AlphaJunoToneName, 36)
      end
    end
  end
end


######################################################################
#  ____       _                 _   ____ ____
# |  _ \ ___ | | __ _ _ __   __| | |  _ \___ \
# | |_) / _ \| |/ _` | '_ \ / _` | | | | |__) |
# |  _ < (_) | | (_| | | | | (_| | | |_| / __/
# |_| \_\___/|_|\__,_|_| |_|\__,_| |____/_____|

class PatchLineEdit < Qt::LineEdit
  slots 'set()'
  def initialize(patch_name, parent)
    super(parent)
    @patch_name = patch_name
    connect(self, SIGNAL('textChanged(const QString &)'),
            self, SLOT('set()'))
    @patch_name.elements.each{ |e| e.add_observer(self) }
    update
  end
  def update
    return if @disable_update
    set_text(@patch_name.map_parent.value(@patch_name))
  end
  def set
    @disable_update = true
    @patch_name.update_elements_and_notify do |parameters|
      padded_text = '%-12s' % text
      padded_text.split('').each_with_index do |char, index|
        parameters[index].set(char[0])
      end
    end
    @disable_update = false
  end
end

class PatchName < ParameterMap
  def initialize(*args)
    super
    12.times do |n|
      param("Patch name #{n+1}", (32..125))
    end
  end
  def value(data)
    data.elements.collect{ |p| p.value.chr }.join.strip
  end
  def special_widget?
    true
  end
  def label
    'Patch name'
  end
  def widget(data, parent)
    @lineedit = PatchLineEdit.new(data, parent)
    @lineedit.max_length = 12
    return @lineedit
  end
end

class WaveListBox < Qt::ListBox
  slots 'set(int)'
  def initialize(wave, names, parent)
    super(parent)
    @wave = wave
    connect(self, SIGNAL('highlighted(int)'),
            self, SLOT('set(int)'))
    insert_string_list(names)
    @wave.add_observer(self)
    update
  end
  def update
    num = @wave.map_parent.number(@wave)
    block_signals(true)
    set_selected(num, true)
    block_signals(false)
    self.top_item = [0, num - 4].max
  end
  def set(wave)
    @wave.update_elements_and_notify do |parameters|
      if wave > 253
        gid = 2
        num = wave - 254
      else
        gid = 1
        num = wave
      end
      high = num >> 4
      low = num & 0xf
      parameters[0].set(0)
      parameters[1].set(gid)
      parameters[2].set(high)
      parameters[3].set(low)
    end
  end
end

class WaveParameter < ParameterMap
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
  
  WAVES =
    (0..253).collect{ |n| "1-#{n+1} #{WAVENAMES[n]}" } +
    (0..250).collect{ |n| "2-#{n+1} #{WAVENAMES[n+254]}" }
  SHORT_WAVES =
    (0..253).collect{ |n| WAVENAMES[n] } +
    (0..250).collect{ |n| WAVENAMES[n+254] }

  def initialize(*args)
    super
    param('Wave group type', (0..0))
    param('Wave group ID', (1..2))
    param('Wave number (high nibble)', (0..15))
    param('Wave number (low nibble)', (0..15))
  end
  def number(data)
    num = (if data.elements[1].value == 2
             254
           else
             0
           end)
    num += data.elements[2].value << 4
    num += data.elements[3].value
  end
  def value(data)
    SHORT_WAVES[number(data)]
  end
  def special_widget?
    true
  end
  def label
    'Wave name'
  end
  def widget(data, parent)
    @list = WaveListBox.new(data, WAVES, parent)
    return @list
  end
end

DeviceClass.new('Roland D2') do |c|
  c.icon = :tone
  c.priority = 1
  c.extend(RolandSysex)
  c.connection_methods << RolandSysex::ConnectionMethods
  c.connection_methods << RandomAccessParameters
  c.family_code = "\x0b\x01"
  c.model_number = "\x03\x00"
  c.version_number = "\x00\x03\x00\x00"

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
          g1.list_entry = :patch
          g1.midi_channel = n0
          g1.offset(0, 'Patch common') do |g2|
            g2.page_entry = true
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
            g1.offset(0x1000 + 0x200 * n1, "Tone #{n1+1}") do |g2|
              g2.list_entry = :tone
              g2.offset(0, 'Tone') do |g3|
                g3.page_entry = true
                g3.offset(0) do |r|
                  r.param('Tone switch', (0..1), %w[Off On])
                end
                g3.add_submap_of_class(WaveParameter, 1)
                g3.offset(5) do |r|
                  r.param('Wave gain', (0..3), WAVE_GAIN)
                  r.param('FXM switch', (0..1), %w[Off On])
                  r.param('FXM color', (0..3))
                  r.param('FXM depth', (0..15))
                end
              end
              g2.offset(0, 'Control') do |g3|
                g3.page_entry = true
                g3.offset(0xb) do |r|
                  r.param('Velocity crossfade', (0..127))
                  r.param('Velocity range lower', (1..127))
                  r.param('Velocity range upper', (1..127))
                  r.param('Keyboard range lower', (0..127))
                  r.param('Keyboard range upper', (0..127))
                end
                g3.offset(0x15) do |r|
                  ['Modulation', 'Pitch bend', 'Aftertouch'].each do |modtype|
                    4.times do |modn|
                      r.param("#{modtype} #{modn+1} destination", (0..15), %w[Off PCH CUT RES LEV PAN L1P L2P L1F L2F L1A L2A PL1 PL2 L1R L2R])
                      r.param("#{modtype} #{modn+1} depth", (0..127))
                    end
                  end
                end
              end
              g2.offset(0x2d, 'Low frequency oscillators') do |r|
                r.page_entry = true
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
              end
              g2.offset(0x3d, 'Pitch') do |r|
                r.page_entry = true
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
              end
              g2.offset(0x50, 'Filter') do |r|
                r.page_entry = true
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
              end
              g2.offset(0x65, 'Amplification') do |r|
                r.page_entry = true
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
    p.offset(0x02_09_00_00, 'Rythm Set') do |g0|
      g0.list_entry = :rythm_set
      g0.offset(0, 'Rythm common') do |g1|
        g1.page_entry = true
        g1.add_submap_of_class(PatchName, 0) do |r|
        end
      end
      (35..98).each do |n0|
        note_name = %w[C C# D D# E F F# G G# A A# B][n0%12] + (n0/12).floor.to_s
        g0.offset(0x100 * n0, "Note #{note_name}") do |g2|
          g2.list_entry = :drum
          g2.midi_channel = 9
          g2.midi_note = n0
          g2.offset(0, 'Tone') do |g1|
            g1.page_entry = true
            g1.offset(0) do |r|
              r.param('Tone switch', (0..1), %w[Off On])
            end
            g1.add_submap_of_class(WaveParameter, 1) do |r|
            end
            g1.offset(5) do |r|
              r.param('Wave gain', (0..3), WAVE_GAIN)
              r.param('Bend range', (0..12))
              r.param('Mute group', (0..32), ['Off'] + (1..31).collect{|n| n.to_s})
              r.param('Envelope mode', (0..1), ['No sustain', 'Sustain'])
            end
          end
          g2.offset(0xc, 'Pitch') do |r|
            r.page_entry = true
            r.param('Coarse tune', (0..96))
            r.param('Fine tune', (0..100))
            r.param('Random pitch depth', (0..30), RANDOM_PITCH_DEPTH)
            r.param('Pitch envelope depth', (0..24))
            r.param('Pitch envelope velocity sens', (0..125))
            r.param('Pitch envelope velocity time', (0..14), KEYFOLLOW2)
            4.times do |n2|
              r.param("Pitch envelope time #{n2}", (0..127))
            end
            4.times do |n2|
              r.param("Pitch envelope level #{n2}", (0..126))
            end
          end
          g2.offset(0x1a, 'Filter') do |r|
            r.page_entry = true
            r.param('Filter type', (0..4), FILTER_TYPE)
            r.param('Cutoff frequency', (0..127))
            r.param('Resonance', (0..127))
            r.param('Resonance velocity sens', (0..125))
            r.param('Filter envelope depth', (0..126))
            r.param('Filter envelope velocity sens', (0..125))
            r.param('Filter envelope velocity time', (0..14), KEYFOLLOW2)
            4.times do |n2|
              r.param("Filter envelope time #{n2}", (0..127))
            end
            4.times do |n2|
              r.param("Filter envelope level #{n2}", (0..127))
            end
          end
          g2.offset(0x29, 'Amplification') do |r|
            r.page_entry = true
            r.param('Tone level', (0..127))
            r.param('Amp envelope velocity sens', (0..125))
            r.param('Amp envelope velocity time', (0..14), KEYFOLLOW2)
            4.times do |n2|
              r.param("Amp envelope time #{n2}", (0..127))
            end
            3.times do |n2|
              r.param("Amp envelope level #{n2}", (0..127))
            end
            r.param('Tone pan', (0..127))
            r.param('Random pan', (0..63))
            r.param('Alternate pan depth', (1..127))
          end
          g2.offset(0x36, 'Output') do |g1|
            g1.page_entry = true
            g1.param('MFX switch', (0..1), %w[Off On])
            g1.offset(0x2) do |r|
              r.param('Delay send level', (0..127))
              r.param('Reverb send level', (0..127))
            end
          end
        end
      end
    end
  end
end
