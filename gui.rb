require 'set'

######################################################################

module ParameterWidget
  def self.included(cls)
    cls.slots 'set(int)'
  end
  def parameter_initialize(data)
    @data = data
    data.add_observer(self)
    signal_connection
  end
  def set(val)
    @data.set(val)
  end
end

class ParameterSlider < Qt::Slider
  include ParameterWidget
  def initialize(data, parent)
    super(data.parameter.range.first,
          data.parameter.range.last,
          1,
          data.value, Qt::Slider::Horizontal, parent)
    parameter_initialize(data)
  end
  def update()
    self.value = @data.value
  end
  def signal_connection
    connect(self, SIGNAL('valueChanged(int)'),
            self, SLOT('set(int)'))
  end
end

class ParameterCombo < Qt::ComboBox
  include ParameterWidget
  def initialize(data, parent)
    super(parent)
    parameter_initialize(data)
  end
  def update()
    set_current_item(@data.value)
  end
  def signal_connection
    connect(self, SIGNAL('activated(int)'),
            self, SLOT('set(int)'))
  end
end

class ParameterListBox < Qt::ComboBox
  include ParameterWidget
  def initialize(data, parent)
    super(parent)
    parameter_initialize(data)
  end
  def update(val)
    set_current_item(val)
  end
  def signal_connection
    connect(self, SIGNAL('activated(int)'),
            self, SLOT('set(int)'))
  end
end

class ParameterWidgets
  def initialize(page, parameter_data_list)
    page.add_widget do |parent|
      @label = Qt::Label.new(parameter_data_list[0].parameter.name, parent)
    end

    parameter_data_list.each do |data|
      parameter = data.parameter
      if (parameter_data_list.length == 1) || !parameter.choices
        page.add_widget do |parent|
          @slider = ParameterSlider.new(data, parent)
        end
        @slider.tick_interval = 1
        @slider.tickmarks = Qt::Slider::Below
        @slider.value = data.value
        # @slider.connect(@slider, SIGNAL('valueChanged(int)'),
        #                 data, SLOT('set(int)'))
        # @slider.connect(data, SIGNAL('changed(int)'),
        #                 @slider, SLOT('setValue(int)'))
      end
      if parameter.choices
        page.add_widget do |parent|
          @combo = ParameterCombo.new(data, parent)
        end
        @combo.insert_string_list(parameter.choices)
        @combo.set_current_item(data.value)
        # @combo.connect(@combo, SIGNAL('activated(int)'),
        #                data, SLOT('set(int)'))
        # @combo.connect(data, SIGNAL('changed(int)'),
        #                @combo, SLOT('setValue(int)'))
      end
    end
    page.new_line
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
    @vbox = Qt::Widget.new(self)
    add_child(@vbox)
    @grid = Qt::GridLayout.new(@vbox)
    self.resize_policy = Qt::ScrollView::AutoOneFit
    set_margins(5,5,5,5)
    @current_x = 0
    @current_y = 0
  end
  def add_widget(width = 1)
    widget = yield @vbox
    @grid.add_multi_cell_widget(widget,
                                @current_y, @current_y,
                                @current_x, @current_x + width - 1)
    @current_x += 1
    if @current_x == 1
      if @current_y == 2
        @grid.set_col_spacing(@current_x, 3)
      end
      @current_x = 2
    end
  end
  def new_line
    @grid.set_row_stretch(@current_y, 0)
    @current_x = 0
    @current_y += 2
    @grid.set_row_spacing(@current_y - 1, 3)
    @grid.set_row_stretch(@current_y, 1)
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

    # TODO: Det här är syntspecifikt. Det ska flyttas. Det är fult också.
    
    case @editor.connection.device_class.name
    when 'Roland D2'
      case data.map_parent.list_entry
      when :patch, :rythm_set
        @name_data = @data.submaps[0][1].submaps[0][1]
      when :tone
        @name_data = @data.submaps[0][1].submaps[1][1]
        @switch = @data.submaps[0][1].submaps[0][1].elements[0]
      when :drum
        @name_data = @data.submaps[0][1].submaps[1][1]
        @switch = @data.submaps[0][1].submaps[0][1].elements[0]
      end
    when 'Alpha Juno'
      case data.map_parent.list_entry
      when :tone
        @name_data = @data.submaps[0][1].submaps[0][1]
      end
    end
    if @name_data
      @name_data.add_observer(self)
      if @switch
        @switch.add_observer(self)
      end
      update
    end
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
  def update
    text = (if @switch.nil? || @switch.value != 0
              @name_data.map_parent.value(@name_data)
            else
              ''
            end)
    set_text(1, text)
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
    self.sizes = [200, 500]
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
    @selected_set.each do |page|
      @connection.auto_read_data_request(*page.data.start_and_length)
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
    build_page(parameter_data_list, page_widget)
    return page_widget
  end
  def build_page(parameter_data_list, page, captions = true)
    if captions # && parameter_data_list.length > 1
      page.add_widget do |parent|
        Qt::Widget.new(parent)
      end
      parameter_data_list.each do |p|
        page.add_widget do |parent|
          Qt::Label.new("<b>#{p.entry_name}</b>", parent)
        end
      end
      page.new_line
    end

    parameter_data = parameter_data_list.first
    width = (if parameter_data_list.length == 1
               3
             else
               parameter_data_list.length + 1
             end)
    if parameter_data.map_parent && parameter_data.map_parent.page_entry
      page.add_widget(width) do |parent|
        Qt::Label.new("<h2>#{parameter_data.map_parent.name}</h2>", parent)
      end
      page.new_line
    end

    if parameter_data.map_parent.special_widget?
      page.add_widget do |parent|
        Qt::Label.new(parameter_data.map_parent.label, parent)
      end
      parameter_data_list.each do |p|
        page.add_widget do |parent|
          p.map_parent.widget(p, parent)
        end
      end
      page.new_line
    else
      element_arrays = parameter_data_list.map{ |pd| pd.elements }
      element_arrays[0].zip(*element_arrays[1..-1]) do |elements|
        ParameterWidgets.new(page, elements)
      end
    end

    unless parameter_data.submaps.empty?
      submap_arrays = parameter_data_list.map{ |pd| pd.submap_objects }
      submap_arrays[0].zip(*submap_arrays[1..-1]) do |submaps|
        unless submaps[0].map_parent && submaps[0].map_parent.list_entry
          build_page(submaps, page, false)
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

def run_gui
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
  window.resize(1000, 700)

  a.main_widget = window
  window.show

  $pixmaps = {}
  $iconsets = {}
  %w[patch tone drum].each do |name_str|
    name = name_str.to_sym
    $pixmaps[name] = Qt::Pixmap.new("#{name}.png")
    $iconsets[name] = Qt::IconSet.new($pixmaps[name])
  end

  a.exec
end
