(
var include_relative = { |relative_path|
	var path = (PathName(thisProcess.nowExecutingPath).pathOnly +/+ relative_path).standardizePath;
	if (File.exists(path)) {
		var result = this.executeFile(path);
		if (result.isNil) { Error("error importing %".format(path)).throw; } { result };
	} {
		Error("include_relative: file % does not exist".format(path.quote)).throw;
	};
};

var ack_engine_root_relative = ".." +/+ ".." +/+ "ack" +/+ "lib";

var lib_root_relative = "lib";
var norns_engine_tester = include_relative.value(lib_root_relative +/+ "norns_engine_tester.scd");
var start_script = norns_engine_tester['start_script'];
var script_name = PathName(thisProcess.nowExecutingPath).fileNameWithoutExtension;

start_script.value(script_name) {

// scriptname: step
// v2.0.0 @jah

var ack = include_relative.value(ack_engine_root_relative +/+ "ack.scd");
var ack_lib = ack[\lib];
var ack_add_params = ack_lib[\add_params];

var prev_grid_width;
var grid_width;
var grid_device;
var arc_device;

var ui_dirty = false;

var refresh_rate = 35;

var event_flash_duration = 0.15;
var event_flash_frame_counter = nil;

var arc_led_x_spec = ControlSpec(1, 64, 'linear', 1, 0, "");
var arc_led_l_spec = ControlSpec(0, 15, 'linear', 1, 0, "");
var tempo_spec = ControlSpec.new(20, 300, 'lin', 0.1, 60, "BPM");
var swing_amount_spec = ControlSpec.new(0, 100, 'lin', 0.1, 0, "%");

var hi_level = 15;
var lo_level = 4;

var enc1_x = 1;
var enc1_y = 13;

var enc2_x = 8;
var enc2_y = 32;

var enc3_x = enc2_x+50;
var enc3_y = enc2_y;

var key2_x = 1;
var key2_y = 64;

var key3_x = key2_x+45;
var key3_y = key2_y;

var num_patterns = 99;
var steps_per_pattern = 16;
var num_tracks = 8;

var pattern_file = "step.data";

var trig_level = 15;
var playpos_level = 7;
var clear_level = 0;

var playing = false;
var queued_playpos;
var playpos = 0;
var sequencer_metro;

var ppqn = 24;
var ticks_to_next;
var odd_ppqn;
var even_ppqn;

var trigs = Array.fill(num_patterns*steps_per_pattern*num_tracks);

var
cutting_is_enabled =
{
	~params.get_("last_row_cuts") == 2
};

var
get_trigs_index =
{ |patternno, stepnum, tracknum|
	((patternno-1)*steps_per_pattern*num_tracks) + ((tracknum-1)*steps_per_pattern) + (stepnum-1)
};

var
set_trig =
{ |patternno, stepnum, tracknum, value|
	var index = get_trigs_index.value(patternno, stepnum, tracknum);
	trigs[index] = value;
};

var
trig_is_set =
{ |patternno, stepnum, tracknum|
	var index = get_trigs_index.value(patternno, stepnum, tracknum);
	trigs[index]
};

var
init_trigs =
{
	(1..num_patterns).do { |patternno|
		(1..steps_per_pattern).do { |stepnum|
			(1..num_tracks).do { |tracknum|
				set_trig.value(patternno, stepnum, tracknum, false);
			}
		}
	}
};

var
get_pattern_length =
{
	if (~params.get_("pattern_length") == 1) {
		8
	} {
		16
	};
};

var
set_pattern_length =
{ |pattern_length|
	var opt;
	if (pattern_length == 8) {
		opt = 1
	} {
		opt = 2
	};
	~params.set__("pattern_length", opt)
};

var
save_patterns =
{
	var filename = ~norns.state.data ++ pattern_file;
	File.use(filename.standardizePath, "w+") { |file|
		(1..num_patterns).do { |patternno|
			(1..num_tracks).do { |tracknum|
				(1..steps_per_pattern).do { |stepnum|
					var int;
					if (trig_is_set.value(patternno, stepnum, tracknum)) {
						int = 1
					} {
						int = 0
					};
					file.write(int.asString ++ "\n");
				};
			};
		};
	};
};

var
load_patterns =
{
	var filename = ~norns.state.data ++ pattern_file;
	if (File.exists(filename.standardizePath)) {
		File.use(filename.standardizePath, "r") { |file|
			(1..num_patterns).do { |patternno|
				(1..num_tracks).do { |tracknum|
					(1..steps_per_pattern).do { |stepnum|
						var line = file.getLine();
						if (line.notNil) {
							set_trig.value(patternno, stepnum, tracknum, line.stripWhiteSpace == "1");
						} {
							Error("file % has invalid pattern file format".format(filename)).throw;
						};
					};
				};
			};
		};
	};
};  

var
tick =
{
	if (queued_playpos.notNil and: (~params.get_("cut_quant") == 1)) {
		ticks_to_next = 0;
	};

	if ((ticks_to_next.isNil) or: (ticks_to_next == 0)) {
		var ts = Array.fill(num_tracks);
		var previous_playpos = playpos;
		if (queued_playpos.notNil) {
			playpos = queued_playpos;
			queued_playpos = nil;
		} {
			playpos = playpos + 1;
			if (playpos > get_pattern_length.value()) {
				playpos = 1;
			};
		};
		(1..num_tracks).do { |tracknum|
			if (trig_is_set.value(~params.get_("pattern"), playpos, tracknum) and: (cutting_is_enabled.value() and: (tracknum == (num_tracks))).not) {
				ts[tracknum-1] = 1;
			} {
				ts[tracknum-1] = 0;
			}
		};
		~engine.multiTrig_(ts[0], ts[1], ts[2], ts[3], ts[4], ts[5], ts[6], ts[7]);

		if (playpos.even) {
			ticks_to_next = even_ppqn;
		} {
			ticks_to_next = odd_ppqn;
		};
		ui_dirty = true;
	};

	ticks_to_next = ticks_to_next - 1;
};

var
update_sequencer_metro_time =
{
	sequencer_metro.time = 60/~params.get_("tempo")/ppqn/~params.get_("beats_per_pattern");
};

var
update_even_odd_ppqn =
{ |swing_amount|
	var swing_ppqn = ppqn*swing_amount/100*0.75;
	even_ppqn = round(ppqn-swing_ppqn);
	odd_ppqn = round(ppqn+swing_ppqn);
};

var
init_sequencer_metro =
{
	sequencer_metro = ~metro.init_();
	update_sequencer_metro_time.value();
	sequencer_metro.event = tick;
};

var
init_pattern_length_param =
{
	~params.add_((
		type: "option",
		id: "pattern_length",
		name: "pattern length",
		options: [8, 16],
		default: 2
	));
};

var
init_pattern_param =
{
	~params.add_((
		type: "number",
		id: "pattern",
		name: "pattern",
		min: 1,
		max: num_patterns,
		default: 1,
		action: {
			ui_dirty = true;
		}
	));
};

var
init_last_row_cuts_param =
{
	~params.add_((
		type: "option",
		id: "last_row_cuts",
		name: "last row cuts",
		options: ["No", "Yes"],
		default: 1
	));
};

var
init_cut_quant_param =
{
	~params.add_((
		type: "option",
		id: "cut_quant",
		name: "quantize cutting",
		options: ["No", "Yes"],
		default: 1
	));
};

var
init_beats_per_pattern_param =
{
	~params.add_((
		type: "number",
		id: "beats_per_pattern",
		name: "beats per pattern",
		min: 1,
		max: 8,
		default: 4,
		action: {
			update_sequencer_metro_time.value();
		}
	));
};

var
init_tempo_param =
{
	~params.add_((
		type: "control",
		id: "tempo",
		name: "tempo",
		controlspec: tempo_spec,
		action: {
			update_sequencer_metro_time.value();
			ui_dirty = true;
		}
	));
};

var
init_swing_amount_param =
{
	~params.add_((
		type: "control",
		id: "swing_amount",
		name: "swing amount",
		controlspec: swing_amount_spec,
		action: { |val|
			update_even_odd_ppqn.value(val);
			ui_dirty = true;
		}
	));
};

var
init_params =
{
	init_pattern_length_param.value();
	init_pattern_param.value();
	init_last_row_cuts_param.value();
	init_cut_quant_param.value();
	init_beats_per_pattern_param.value();
	init_tempo_param.value();
	init_swing_amount_param.value();
	~params.add_separator_();
	ack_add_params.value();
};

var
flash_event =
{
	event_flash_frame_counter = round(event_flash_duration * refresh_rate);
};
  
var
event_indicator_should_be_shown =
{
	event_flash_frame_counter.notNil
};

var
update_event_indicator =
{
	if (event_flash_frame_counter.notNil) {
		event_flash_frame_counter = event_flash_frame_counter - 1;
		case
		{ event_flash_frame_counter <= 0 } {
			event_flash_frame_counter = nil;
		};
		ui_dirty = true;
	};
};

var
refresh_grid_button =
{ |x, y|
	if (cutting_is_enabled.value() and: (y == 8)) {
		if (x == playpos) {
			grid_device.led_(x, y, playpos_level);
		} {
			grid_device.led_(x, y, clear_level);
		};
	} {
		case {trig_is_set.value(~params.get_("pattern"), x, y)} {
			grid_device.led_(x, y, trig_level)
		}
		{ x == playpos } {
			grid_device.led_(x, y, playpos_level)
		}
		{ true } {
			grid_device.led_(x, y, clear_level)
		}
	};
};

var
refresh_grid_column =
{ |x|
	(1..num_tracks).do { |y|
		refresh_grid_button.value(x, y)
	};
};

var
refresh_grid =
{
	(1..steps_per_pattern).do { |stepnum|
		refresh_grid_column.value(stepnum)
	};

	grid_device.refresh_();
};

var
update_grid_width =
{
	if (grid_device.device_.notNil) {
		if (grid_width != grid_device.cols_) {
			grid_width = grid_device.cols_;
		};
	};
};

var
refresh_arc =
{
	arc_device.all_(0);
	arc_device.led_(1, arc_led_x_spec.map(~params.get_raw_("tempo")), arc_led_l_spec.maxval);
	arc_device.led_(2, arc_led_x_spec.map(~params.get_raw_("swing_amount")), arc_led_l_spec.maxval);
	arc_device.refresh_();
};

var
refresh_ui =
{
	update_event_indicator.value();
	update_grid_width.value();

	if (prev_grid_width != grid_width) {
		set_pattern_length.value(grid_width);
		prev_grid_width = grid_width;
		ui_dirty = true;
	};

	if (ui_dirty) {
		~redraw.value();
		refresh_arc.value();
		refresh_grid.value();
		ui_dirty = false;
	};
};

var
init_ui_refresh_metro =
{
	var ui_refresh_metro = ~metro.init_();
	ui_refresh_metro.event = refresh_ui;
	ui_refresh_metro.time = 1/refresh_rate;
	ui_refresh_metro.start_();
};

var
init_arc =
{
	arc_device = ~arc.connect_();
	arc_device[\delta] = { |n, delta| // not .delta notation to suppress self argument?
		case {n == 1} {
			var val = ~params.get_raw_("tempo");
			~params.set_raw_("tempo", val+(delta/500));
		}
		{n == 2} {
			var val = ~params.get_raw_("swing_amount");
			~params.set_raw_("swing_amount", val+(delta/500));
		};
		flash_event.value();
		ui_dirty = true;
	};
};

var
init_grid =
{
	grid_device = ~grid.connect_();
	grid_device[\key] = { |x, y, state|
		if (state == 1) {
			if (cutting_is_enabled.value() and: (y == 8)) {
				queued_playpos = x;
			} {
				set_trig.value(
					~params.get_("pattern"),
					x,
					y,
					trig_is_set.value(~params.get_("pattern"), x, y).not
				);
			}
		};
		flash_event.value();
		ui_dirty = true;
	};
};

var
init_ui =
{
	init_arc.value();
	init_grid.value();
	init_ui_refresh_metro.value();
};

var
get_play_label =
{
	if (playing) {
		"PLAY " ++ playpos;
	} {
		"PLAY";
	};
};

var
redraw_enc1_widget =
{
	~screen.move_(enc1_x, enc1_y);
	~screen.level_(lo_level);
	~screen.text_("LEVEL");
	~screen.move_(enc1_x+45, enc1_y);
	~screen.level_(hi_level);
	~screen.text_(round(~params.get_raw_("main_level") * 100, 1));
};

var
redraw_param_widget =
{ |x, y, label, value|
	~screen.move_(x, y);
	~screen.level_(lo_level);
	~screen.text_(label);
	~screen.move_(x, y+12);
	~screen.level_(hi_level);
	~screen.text_(value);
};

var
redraw_enc2_widget =
{
	redraw_param_widget.value(enc2_x, enc2_y, "BPM", ~params.get_("tempo"));
};

var
redraw_enc3_widget =
{
	redraw_param_widget.value(enc3_x, enc3_y, "SWING", ~params.get_("swing_amount").asString ++ "%");
};

var
redraw_key2_widget =
{
	~screen.move_(key2_x, key2_y);
	if (playing) {
		~screen.level_(lo_level);
	} {
		~screen.level_(hi_level);
	};
	~screen.text_("STOP");
};

var
redraw_key3_widget =
{
	~screen.move_(key3_x, key3_y);
	if (playing) {
		~screen.level_(hi_level);
	} {
		~screen.level_(lo_level);
	};
	~screen.text_(get_play_label.value());
};

var
redraw_event_flash_widget =
{
	~screen.level_(lo_level);
	~screen.rect_(122, enc1_y-7, 5, 5);
	~screen.fill_();
};

~
engine.name = 'Ack'
;

~
init =
{
	init_trigs.value();
	init_params.value();
	init_sequencer_metro.value();
	load_patterns.value();
	init_ui.value();
	~params.read_();
	~params.bang_();
};

~
cleanup =
{
	~params.write_();
	save_patterns.value();

	if (grid_device.device_.notNil) {
		grid_device.all_(0);
		grid_device.refresh_();
	};
};

~
redraw =
{
	~screen.font_size_(16);
	~screen.clear_();

	redraw_enc1_widget.value();

	if (event_indicator_should_be_shown.value()) {
		redraw_event_flash_widget.value();
	};

	redraw_enc2_widget.value();
	redraw_enc3_widget.value();
	redraw_key2_widget.value();
	redraw_key3_widget.value();
	~screen.update_();
};

~
enc =
{ |n, delta|
	case {n == 1} {
		~params.delta_("main_level", delta);
		ui_dirty = true;
	}
	{n == 2} {
		~params.delta_("tempo", delta);
	}
	{n == 3} {
		~params.delta_("swing_amount", delta);
	};
};

~
key =
{ |n, s|
	case {(n == 2) and: (s == 1)} {
		if (playing == false) {
			playpos = 0;
			queued_playpos = 1;
		} {
			playing = false;
			sequencer_metro.stop_();
		}
	}
	{(n == 3) and: (s == 1)} {
		playing = true;
		sequencer_metro.start_();
	};
	ui_dirty = true;
};


};
)
