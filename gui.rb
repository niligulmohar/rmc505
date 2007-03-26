class PatchEditor < Qt::Splitter
  def initialize(*args)
    super
    foo0 = Qt::Widget.new(self)
    foo1 = Qt::Widget.new(self)
  end
end

######################################################################

class LogDevice < Logger::LogDevice
  def write(message)
    super
    $log_widget.append(message.chop)
  end
end

class MainWindow < KDE::MainWindow
  slots 'idle()'

  def initialize(name)
    super(nil, name)
    setCaption(name)

    @timer = Qt::Timer.new
    connect(@timer, SIGNAL('timeout()'), self, SLOT('idle()'))
    @timer.start(0)
    # KDE::StdAction.quit(self, SLOT('close()'), actionCollection())
    # KDE::Action.new(i18n('Reload parameters'), 'reload', KDE::Shortcut.new(0), self, SLOT('reload()'), actionCollection(), 'reload')
    # KDE::Action.new(i18n('Send snapshot of parameters'), 'filesave', KDE::Shortcut.new(0), self, SLOT('snapshot()'), actionCollection(), 'snapshot')
    # @checkbox = KDE::ToggleAction.new(i18n('Auto trigger note'), 'player_play', KDE::Shortcut.new(0), self, SLOT('reload()'), actionCollection(), 'autotrigger')
    # @trigger = Qt::HBox.new(nil)
    # @trigger.set_spacing(5)
    # Qt::Label.new('Auto trigger note', @trigger)
    # #@checkbox = Qt::CheckBox.new(@trigger)
    # @checkbox.set_checked($note_trigger.enabled)
    # @notebox = Qt::SpinBox.new(1, 128, 1, @trigger)
    # @notebox.value = $note_trigger.note
    # Qt::Label.new('Velocity', @trigger)
    # @velocitybox = Qt::SpinBox.new(1, 127, 1, @trigger)
    # @velocitybox.value = $note_trigger.velocity
    # connect(@checkbox, SIGNAL('toggled(bool)'), $note_trigger, SLOT('enabled=(bool)'))
    # connect(@notebox, SIGNAL('valueChanged(int)'), $note_trigger, SLOT('note=(int)'))
    # connect(@velocitybox, SIGNAL('valueChanged(int)'), $note_trigger, SLOT('velocity=(int)'))
    # KDE::WidgetAction.new(@trigger, 'Gurk', KDE::Shortcut.new(0), self, SLOT('idle()'), actionCollection(), 'note_trigger')

    #createGUI
    createGUI(Dir.getwd + "/rmc505ui.rc")

    @tabs = Qt::TabWidget.new(self)
    set_central_widget(@tabs)
    @tab0 = Qt::Widget.new(self)
    grid = Qt::GridLayout.new(@tab0, 1, 1)
    $log_widget = Qt::TextBrowser.new(@tab0)
    $log_widget.text_format = Qt::LogText
    $log_widget.set_font(Qt::Font.new('lucida console, courier'))
    grid.add_widget($log_widget, 0, 0)
    @tabs.add_tab(@tab0, 'Log')

    initialize_app(LogDevice) do |midi|
      midi.new_connection do |connection|
        tab = Qt::Widget.new(self)
        grid = Qt::GridLayout.new(tab, 1, 1)
        patch_editor = PatchEditor.new(tab)
        grid.add_widget(patch_editor, 0, 0)
        @tabs.add_tab(tab, connection.name)
        if @tabs.current_page_index == 0
          @tabs.current_page = 1
        end
      end
    end
  end

  def idle
    $midi.pump
    # Sometimes, this timer just stops working. This seems to fix it:
    @timer.start(0)
  end

end

######################################################################

about = KDE::AboutData.new('rmc505',
                           'Rmc505',
                           '0.1.0',
                           'A Roland MC505/D2 patch editor',
                           KDE::AboutData::License_GPL,
                           '(C) 2006-2007 Nicklas Lindgren')
about.add_author('Nicklas Lindgren',
                 'Programmer',
                 'nili@lysator.liu.se')

KDE::CmdLineArgs.init(ARGV, about)
a = KDE::Application.new()

window = MainWindow.new('Rmc505')
window.resize(800, 600)

a.main_widget = window
window.show

a.exec
