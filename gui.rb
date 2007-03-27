class PatchEditorPage < Qt::ListViewItem
  def initialize(editor, data, parent)
    super(parent)
    @data = data
    @editor = editor
  end
  def text=(text)
    set_text(0, text)
  end
  def pixmap=(pixmap)
    set_pixmap(0, pixmap)
  end
  def activate
    @editor.stack.raise_widget(page_widget)
    @editor.sizes = [200, 600]
  end
  def page_widget
    unless @page_widget
      @page_widget = Qt::Widget.new(@editor.stack)
      grid = Qt::GridLayout.new(@page_widget, 1, 1)
      scroll = Qt::ScrollView.new(@page_widget)
      grid.add_widget(scroll, 0, 0)
      @vbox = Qt::VBox.new(scroll.viewport)
      scroll.add_child(@vbox)
      scroll.resize_policy = Qt::ScrollView::AutoOneFit
      scroll.set_margins(5,5,5,5)
      @editor.build_page(@data, @vbox)
    end
    return @page_widget
  end
end

class PatchEditor < Qt::Splitter
  attr_reader :stack
  def initialize(connection, *args)
    super(*args)
    @list_view = KDE::ListView.new(self)
    @list_view.add_column('Page', -1)
    @list_view.selection_mode = Qt::ListView::Extended
    @list_view.root_is_decorated = true
    @list_view.header.hide
    @list_view.set_sorting(-1)

    @stack = Qt::WidgetStack.new(self)

    @connection = connection
    if @connection.parameter_data
      build_tree(@connection.parameter_data, @list_view)
    end
  end

  def build_tree(parameter_data, parent)
    if parameter_data.map_parent && parameter_data.map_parent.list_entry
      widget = PatchEditorPage.new(self, parameter_data, parent)
      widget.text = parameter_data.map_parent.name
      if parameter_data.map_parent.list_entry.kind_of?(Symbol)
        if $pixmaps.has_key?(parameter_data.map_parent.list_entry)
          widget.pixmap = $pixmaps[parameter_data.map_parent.list_entry]
        end
      end
      sub_parent = widget
      unless parameter_data.elements.empty? || parameter_data.map_parent.box
        $logger.debug('params here??')
      end
    else
      sub_parent = parent
    end
    parameter_data.submaps.reverse.each do |r, submap|
      build_tree(submap, sub_parent)
    end
  end
  def build_page(parameter_data, vbox, group_param = nil)
    if parameter_data.map_parent && parameter_data.map_parent.box
      group = Qt::GroupBox.new(2, Qt::GroupBox::Horizontal, vbox)
      group.title = parameter_data.map_parent.name
    else
      group = group_param
    end
    parameter_data.elements.each do |element|
      parameter = element.parameter
      @label = Qt::Label.new(parameter.name, group)
      box = Qt::HBox.new(group)
      @slider = Qt::Slider.new(parameter.range.first, parameter.range.last, 1, element.value, Qt::Slider::Horizontal, box)
      @slider.tick_interval = 1
      @slider.tickmarks = Qt::Slider::Below
      @slider.value = element.value
      #connect(@slider, SIGNAL('valueChanged(int)'), self, SLOT('change(int)'))
      if parameter.choices
        @combo = Qt::ComboBox.new(box)
        @combo.insert_string_list(parameter.choices)
        @combo.set_current_item(element.value)
        #connect(@combo, SIGNAL('activated(int)'), @slider, SLOT('setValue(int)'))
      end
    end
    parameter_data.submaps.each do |r, submap|
      unless submap.map_parent && submap.map_parent.list_entry
        build_page(submap, vbox, group)
      end
    end
  end
end

######################################################################

class LogDevice < Logger::LogDevice
  def write(message)
    super
    $log_widget.append(message.chop.gsub('<','&lt;').gsub('>','&gt;'))
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
    $log_widget.set_font(Qt::Font.new('courier'))
    grid.add_widget($log_widget, 0, 0)
    @tabs.add_tab(@tab0, 'Log')

    initialize_app(LogDevice) do |midi|
      midi.new_connection do |connection|
        tab = Qt::Widget.new(self)
        grid = Qt::GridLayout.new(tab, 1, 1)
        patch_editor = PatchEditor.new(connection, tab)
        grid.add_widget(patch_editor, 0, 0)
        @tabs.add_tab(tab, connection.name)
        if connection.device_class.icon
          @tabs.set_tab_icon_set(tab, $iconsets[connection.device_class.icon])
        end
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

$pixmaps = {}
$iconsets = {}
%w[patch tone drum].each do |name|
  $pixmaps[name.to_sym] = Qt::Pixmap.new("#{name}.png")
  $iconsets[name.to_sym] = Qt::IconSet.new($pixmaps[name.to_sym])
end

a.exec
