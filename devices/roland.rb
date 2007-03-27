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
    event.variable_data =~ /^\xf0#{manufacturer_id.chr}#{sysex_channel.chr}\x00#{family_code[0..0]}\x12/
  end
end

module RandomAccessParameters
end

module TimedBulkParameters
end

######################################################################
#  ____   ____ ____         _    _____  ___
# |  _ \ / ___|  _ \       / \  |___ / / _ \
# | |_) | |   | |_) |____ / _ \   |_ \| | | |
# |  __/| |___|  _ <_____/ ___ \ ___) | |_| |
# |_|    \____|_| \_\   /_/   \_\____/ \___/

DeviceClass.new('PCR-A30') do |c|
  c.icon = :patch
  c.extend(RolandSysex)
  c.extend(TimedBulkParameters)
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
           L1 L2 L3 P1 P2].each_with_index do |c, n|
          m.offset(n * 0x100, c) do |cg|
            cg.list_entry = true
            cg.box = true
            128.times do
              cg.param('Unknown', (0..127))
            end
          end
        end
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

DeviceClass.new('Roland D2') do |c|
  c.icon = :tone
  c.extend(RolandSysex)
  c.extend(RandomAccessParameters)
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
            g2.box = true
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
                g3.box = true
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
                g3.box = true
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
              g2.offset(0x15 + 6, 'Low frequency oscillators') do |r|
                r.box = true
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
              g2.offset(0x15 + 6 + 16, 'Pitch') do |r|
                r.box = true
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
              g2.offset(0x15 + 6 + 16 + 19, '...') do |r|
                r.box = true
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
    p.offset(0x02_09_00_00, 'Rythm Set') do |g0|
      g0.list_entry = true
      g0.offset(0, 'Common') do |g1|
        g1.add_submap_of_class(PatchName, 0) do |r|
        end
      end
      (35..98).each do |n0|
        note_name = %w[C C# D D# E F F# G G# A A# B][n0%12] + (n0/12).floor.to_s
        g0.offset(0x100 * n0, "Note #{note_name}") do |g1|
          g1.list_entry = :drum
          g1.box = true
          g1.midi_channel = 9
          g1.midi_note = n0
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
          g1.offset(0xc) do |r|
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
            r.param('MFX switch', (0..1), %w[Off On])
          end
          g1.offset(0x38) do |r|
            r.param('Delay send level', (0..127))
            r.param('Reverb send level', (0..127))
          end
        end
      end
    end
  end
end
