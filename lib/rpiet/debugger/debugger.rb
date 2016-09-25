require 'jrubyfx'
require 'thread'

module RPiet
  class Debugger < JRubyFX::Application
    WINDOW_DIM = 800 
    CODEL_DIM = 20
    NORMAL = Java::javafx.scene.paint.Color.web("0x222222")
    CANDIDATE = Java::javafx.scene.paint.Color::YELLOW
    BREAKPOINT = Java::javafx.scene.paint.Color::RED
    CURRENT = Java::javafx.scene.paint.Color::CADETBLUE
    WHITE = Java::javafx.scene.paint.Color::WHITE
#    AUTO_STEP_TIME = 1
    LABEL_CSS = {text_fill: WHITE, style: "-fx-padding: 3"}
    include JRubyFX

    def self.instance
      @@instance
    end

    def calculate_pixels_per_codel
      WINDOW_DIM / [@rpiet.source.rows, @rpiet.source.cols].max
    end
    
    def break_point?(x,y)
      @break_points["#{x}x#{y}"]
    end

    def update_connector(start_x, start_y, end_x, end_y)
      size = calculate_pixels_per_codel
      @stage["#connector"].tap do |connector|
        connector.start_x = size/2 + (start_x + 1) * size
        connector.start_y = size/2 + (start_y + 1) * size
        connector.end_x = size/2 + (end_x + 1) * size
        connector.end_y = size/2 + (end_y + 1) * size
      end
    end

    def begin_session
      update_connector(-1, 0, 0, 0)
    end

    def highlight_candidate(runtime, edge_x, edge_y, next_x, next_y, valid)
      size = calculate_pixels_per_codel
      update_connector(edge_x, edge_y, next_x, next_y)
      # Replace with black edge in debugger later
      if next_x < 0 || next_y < 0 || next_x >= @rpiet.source.cols || next_y >= @rpiet.source.rows
        puts "OUT OF BOUNDS #{next_x} #{next_y} #{@rpiet.source.rows} #{@rpiet.source.cols}"
        return
      end
      run_later do
        @stage["\##{next_x}x#{next_y}"].stroke = CANDIDATE
        if @lastc_x
          color = break_point?(@lastc_x, @lastc_y) ? BREAKPOINT : NORMAL
          if color == NORMAL && @stage["\##{@lastc_x}x#{@lastc_y}"].stroke != CURRENT
            @stage["\##{@lastc_x}x#{@lastc_y}"].stroke = color
          end
        end
        @lastc_x, @lastc_y = next_x, next_y
      end
    end

    def highlight(runtime, x, y)
      run_later do
        @stage["\##{x}x#{y}"].stroke = CURRENT
        if @last_x
          color = break_point?(@last_x, @last_y) ? BREAKPOINT : NORMAL
          @stage["\##{@last_x}x#{@last_y}"].stroke = color
        end
        @last_x, @last_y = x, y
        @stage["#dp"].rotate = runtime.pvm.dp.degrees
        @stage["#cc"].rotate = runtime.pvm.cc.degrees(runtime.pvm.dp)
      end
    end

    def operation(runtime, oper)
      run_later do
        @stage['#oper'].text = "oper: " + oper.to_s
        @stage['#stack'].text = "stack: " + runtime.pvm.stack.inspect
        @stage['#bv'].text = "value: " + runtime.pvm.block_value.inspect
      end
    end

    ##
    # JavaFX has some caching so we cheat the cache by using file: uri and varying the uri by adding
    # a time param.
    def reload_stylesheet(scene)
      scene.stylesheets.clear

      name = File.join('file:' + File.dirname(__FILE__), (@odd_load_css ? '/./' : '') + "stylesheet.css")

      puts "NAME #{name}"
      scene.stylesheets.add(name)
      @odd_load_css = !@odd_load_css
    end

    def watch_stylesheet(scene)
      file = File.join(File.dirname(__FILE__), "stylesheet.css")
      last_time = File.mtime(file)
      Thread.new do
        loop do
          mtime = File.mtime(file)

          if mtime != last_time
            reload_stylesheet(scene)
            last_time = mtime
          else
            sleep 1
          end
        end
      end.run
    end

    def start(stage)
      @rpiet = $rpiet # how does jrubyfx pass params before start is called?
      @break_points = break_points = {}
      @stage = stage
      debugger = self
      pixels = @rpiet.source.pixels
      rpiet = @rpiet
      size = calculate_pixels_per_codel
      n = CODEL_DIM
      arc_n = size / 6
      stroke_width = size / 10
      width, height = (@rpiet.source.cols + 2) * size, (@rpiet.source.rows + 2) * size + 90
      with(stage, title: "RPiet", width: width, height: height) do
        layout_scene do
          vbox(id: 'main') do
            border_pane do
              top(menu_bar! do
                menu("File") do
                  menu_item("Quit") do
                    set_on_action do |event|
                      rpiet.abort
                      Platform.exit
                    end
                  end
                end
                menu("View") do
                  menu_item("Reload Stylesheet") { set_on_action { |_| debugger.reload_stylesheet(stage.scene) } }
                end
              end)
              left(hbox(style: "-fx-padding: 8") do
                     label("dp:", LABEL_CSS)
                     polygon([2, 9, 11, 9, 10, 4, 18, 10, 10, 16, 11, 11, 2, 11].to_java(:double), stroke_width: 6, fill: WHITE, id: 'dp', style: "-fx-padding: 3")
                     label("cc:", text_fill: WHITE, style: "-fx-padding: 3")
                     polygon([2, 9, 11, 9, 10, 4, 18, 10, 10, 16, 11, 11, 2, 11].to_java(:double), stroke_width: 6, fill: WHITE, id: 'cc', style: "-fx-padding: 3")
                     label("oper:", {id: 'oper'}.merge(LABEL_CSS))
                     label("value: ", {id: 'bv'}.merge(LABEL_CSS))
                     label("stack:", {id: 'stack'}.merge(LABEL_CSS))
                   end)
              right(hbox do
                get_style_class.add "controls"
                button("restart") do
                  get_style_class.add "control"
                  set_on_action { |_| rpiet.restart }
                end
                button("pause") do
                  get_style_class.add "control"
                  set_on_action { |_| rpiet.pause }
                end
                button("resume") do
                  get_style_class.add "control"
                  set_on_action { |_| rpiet.resume }
                end
                button("step") do
                  get_style_class.add "control"
                  set_on_action { |_| rpiet.advance }
                end
              end)
            end
            group do

              # Horizontal top and bottom border
              (rpiet.source.cols + 2).times do |i|
                rectangle(i*size, 0, size-1, size-1, stroke_type: :inside, stroke: NORMAL) do
                  get_style_class.add "out-of-bounds"
                end
                rectangle(i*size, (rpiet.source.rows + 1)*size, size-1, size-1,
                          stroke_type: :inside, stroke: NORMAL) do
                  get_style_class.add "out-of-bounds"
                end
              end

              # Left and right vertical border
              group do
                rpiet.source.rows.times do |j|
                  rectangle(0, (j + 1) * size, size-1, size-1, stroke_type: :inside, stroke: NORMAL) do
                    get_style_class.add "out-of-bounds"
                  end

                  rectangle((rpiet.source.cols + 1) * size, (j + 1) * size, size-1, size-1,
                            stroke_type: :inside, stroke: NORMAL) do
                    get_style_class.add "out-of-bounds"
                  end
                end
              end

              pixels.each_with_index do |row, i|
                row.each_with_index do |piet_pixel, j|
                  color = Java::javafx.scene.paint.Color.web(piet_pixel.rgb)
                  ident = "#{i}x#{j}"
                  rectangle((i+1)*size, (j+1)*size, size-1, size-1, fill: color,
                            arc_width: arc_n, arc_height: arc_n, 
                            stroke_type: :inside, stroke_width: stroke_width,
                            stroke: NORMAL, stroke_line_join: :round,
                            id: ident) do
                    get_style_class.add "codel"
                    set_on_mouse_clicked do |event|
                      new_color = if event.source.stroke == BREAKPOINT
                                    break_points[ident] = nil
                                    NORMAL
                                  else
                                    break_points[ident] = event.source
                                    BREAKPOINT
                                  end
                      event.source.stroke = new_color
                    end
                  end
                end
              end
              # FIXME: stroke_width must be derived but I feel I need to add scrolling and a minimum
              # codel display size before I can do this.
              line(start_x: (size/2), start_y: size + (size/2), end_x: size + (size/2), end_y: size + (size/2),
                   stroke_width: 10, id: 'connector')
            end
          end
        end
      end.show
      $event_handler.debugger_started self
      reload_stylesheet(stage.scene)
      watch_stylesheet(stage.scene)
    end
  end
end
