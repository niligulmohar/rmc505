require 'set'

######################################################################

class ParameterWidgets
  def initialize(parent_param, parameter_data_list)
    @label = Qt::Label.new(parameter_data_list[0].parameter.name, parent_param)
    if parameter_data_list.length == 1
      parent = Qt::HBox.new(parent_param)
    else
      parent = parent_param
    end

    parameter_data_list.each do |data|
      parameter = data.parameter
      if (parameter_data_list.length == 1) || !parameter.choices
        @slider = Qt::Slider.new(parameter.range.first, parameter.range.last, 1, data.value, Qt::Slider::Horizontal, parent)
        @slider.tick_interval = 1
        @slider.tickmarks = Qt::Slider::Below
        @slider.value = data.value
        #connect(@slider, SIGNAL('valueChanged(int)'), self, SLOT('change(int)'))
      end
      if parameter.choices
        @combo = Qt::ComboBox.new(parent)
        @combo.insert_string_list(parameter.choices)
        @combo.set_current_item(data.value)
        #connect(@combo, SIGNAL('activated(int)'), @slider, SLOT('setValue(int)'))
      end
    end
  end
end

class GroupScrollView < Qt::ScrollView
  slots 'contentsMoving(int,int)'
  def initialize(parent, editor, group)
    super(parent)
    @editor = editor
    @group = group
    connect(self, SIGNAL('contentsMoving(int, int)'),
            self, SLOT('contentsMoving(int, int)'))
    @new_state = :new
  end
  def scroll
    unless @new_state
      if @editor.scroll_positions.has_key?(@group)
        y = @editor.scroll_positions[@group]
        set_contents_pos(0, y)
      end
    end
  end
  def contentsMoving(x, y)
    @editor.scroll_positions[@group] = y
  end
  def viewportPaintEvent(pe)
    super
    if @new_state
      @new_state = false
      # Undrar om det finns något snyggare sätt att lösa det här.
      # scroll() fungerar inte i polish eller i koden strax efter att
      # widgeten skapats.
      scroll
    end
  end
end

class PatchEditorPage < Qt::ListViewItem
  attr_reader :data
  slots 'contentsMoving(int, int)'
  def initialize(editor, data, parent)
    super(parent)
    @data = data
    @editor = editor
  end
  def list_entry
    @data.map_parent.list_entry
  end
  def text=(text)
    set_text(0, text)
  end
  def pixmap=(pixmap)
    set_pixmap(0, pixmap)
  end
  def scroll
    @page_widget.scroll if @page_widget
  end
  def setSelected(state)
    super
    @editor.selected_set.send((state ? :add : :delete), self)
  end
  def page_widget
    unless @page_widget
      @page_widget = @editor.page_widget_for([@data])
    end
    return @page_widget
  end
end

class PatchEditor < Qt::Splitter
  slots 'selectionChanged()'
  attr_reader :stack, :connection, :selected_set, :scroll_positions
  def initialize(connection, *args)
    super(*args)
    @list_view = KDE::ListView.new(self)
    @list_view.add_column('Page', -1)
    @list_view.add_column('Name', -1)
    @list_view.set_all_columns_show_focus(true)
    @list_view.resize_mode = Qt::ListView::LastColumn
    @list_view.selection_mode = Qt::ListView::Extended
    @list_view.root_is_decorated = true
    @list_view.header.hide
    @list_view.set_sorting(-1)
    connect(@list_view, SIGNAL('selectionChanged()'),
            self, SLOT('selectionChanged()'))

    @stack = Qt::WidgetStack.new(self)
    @empty_widget = Qt::Widget.new(@stack)
    @temp_widget = nil

    @connection = connection
    if @connection.parameter_data
      build_tree(@connection.parameter_data, @list_view)
    end

    @selected_set = Set.new
    @scroll_positions = {}

    set_sizes
  end
  def set_sizes
    self.sizes = [200, 600]
  end
  def selectionChanged
    if @temp_widget
      @temp_widget.dispose
    end
    if @selected_set.length == 0
      @stack.raise_widget(@empty_widget)
    elsif @selected_set.length == 1
      @selected_set.each do |page|
        @stack.raise_widget(page.page_widget)
        page.scroll
      end
    else
      entry_types = Set.new
      @selected_set.each do |page|
        entry_types.add(page.list_entry)
      end
      if entry_types.length == 1
        @temp_widget = page_widget_for(@selected_set.collect{ |p| p.data }.sort)
        @stack.raise_widget(@temp_widget)
      else
        @stack.raise_widget(@empty_widget)
      end
    end
    # @editor.stack.raise_widget(page_widget)
    # @editor.set_sizes
    # $logger.debug('foo')
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
      unless parameter_data.elements.empty? || parameter_data.map_parent.page_entry
        $logger.debug('params here??')
      end
    else
      sub_parent = parent
    end
    parameter_data.submaps.reverse.each do |r, submap|
      build_tree(submap, sub_parent)
    end
  end
  def page_widget_for(parameter_data_list)
    entry_type = parameter_data_list.first.map_parent.list_entry
    page_widget = GroupScrollView.new(@stack, self, entry_type)
    vbox = Qt::VBox.new(page_widget)
    page_widget.add_child(vbox)
    page_widget.resize_policy = Qt::ScrollView::AutoOneFit
    page_widget.set_margins(5,5,5,5)
    build_page(parameter_data_list, vbox, nil)
    return page_widget
  end
  def build_page(parameter_data_list, vbox, group_param)
    parameter_data = parameter_data_list.first
    if parameter_data.map_parent && parameter_data.map_parent.page_entry
      group = Qt::GroupBox.new(parameter_data_list.length + 1,
                               Qt::GroupBox::Horizontal,
                               vbox)
      group.title = parameter_data.map_parent.name
      if parameter_data_list.length > 1
        Qt::Widget.new(group)
        parameter_data_list.each do |p|
          Qt::Label.new(p.entry_name, group)
        end
      end
    else
      group = group_param
    end

    element_arrays = parameter_data_list.map{ |pd| pd.elements }
    element_arrays[0].zip(*element_arrays[1..-1]) do |elements|
      ParameterWidgets.new(group, elements)
    end

    unless parameter_data.submaps.empty?
      submap_arrays = parameter_data_list.map{ |pd| pd.submap_objects }
      submap_arrays[0].zip(*submap_arrays[1..-1]) do |submaps|
        unless submaps[0].map_parent && submaps[0].map_parent.list_entry
          build_page(submaps, vbox, group)
        end
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

    @start_time = Time.now
    @timer = Qt::Timer.new
    connect(@timer, SIGNAL('timeout()'), self, SLOT('idle()'))
    @timer.start(0)

    #createGUI
    createGUI(Dir.getwd + "/rmc505ui.rc")

    @tabs = Qt::TabWidget.new(self)
    set_central_widget(@tabs)
    log_tab = Qt::Widget.new(self)
    grid = Qt::GridLayout.new(log_tab, 1, 1)
    $log_widget = Qt::TextBrowser.new(log_tab)
    $log_widget.text_format = Qt::LogText
    $log_widget.set_font(Qt::Font.new('courier'))
    grid.add_widget($log_widget, 0, 0)
    @tabs.add_tab(log_tab, 'Log')

    initialize_app(LogDevice) do |midi|
      midi.new_connection do |connection|
        patch_editor = PatchEditor.new(connection, @tabs)
        @tabs.add_tab(patch_editor, connection.name)
        if connection.device_class.icon
          @tabs.set_tab_icon_set(patch_editor, $iconsets[connection.device_class.icon])
        end
        if @tabs.current_page_index == 0
          @tabs.show_page(patch_editor)
        elsif just_started?
          if connection.device_class.priority <
              @tabs.current_page.connection.device_class.priority
            @tabs.show_page(patch_editor)
          end
        end
      end
    end
  end

  def idle
    $midi.pump
    # Sometimes, this timer just stops working. This seems to fix it:
    @timer.start(0)
  end

  def just_started?
    Time.now - @start_time < 2
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
