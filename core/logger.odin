package core

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:terminal/ansi"
import "core:time"


@(private = "file")
global_subtract_stdout_options: log.Options
@(private = "file")
global_subtract_stderr_options: log.Options

logger_setup :: proc() -> runtime.Logger {

	file_mode := 0
	when ODIN_OS == .Linux || ODIN_OS == .Darwin {
		file_mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
	}

	file_name := "bedbug.log"
	log_handle, err := os.open(file_name, (os.O_CREATE | os.O_TRUNC | os.O_RDWR), file_mode)
	assert(err == os.ERROR_NONE, fmt.tprintf("failed to open file '%s': %v", file_name, err))

	console_logger := log.create_console_logger()
	console_logger.procedure = _console_logger_proc
	file_logger := log.create_file_logger(log_handle)
	file_logger.procedure = _file_logger_proc

	return log.create_multi_logger(console_logger, file_logger)
}

@(private = "file")
_file_logger_proc :: proc(
	logger_data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	data := cast(^log.File_Console_Logger_Data)logger_data
	_logger_proc(data.file_handle, data.ident, level, text, options, location)
}

@(private = "file")
_console_logger_proc :: proc(
	logger_data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {

	options := options
	data := cast(^log.File_Console_Logger_Data)logger_data
	h: os.Handle = ---

	if level < log.Level.Error {
		h = os.stdout
		options -= global_subtract_stdout_options
	} else {
		h = os.stderr
		options -= global_subtract_stderr_options
	}

	_logger_proc(h, data.ident, level, text, options, location)
}

@(private = "file")
_logger_proc :: proc(
	h: os.Handle,
	ident: string,
	level: log.Level,
	text: string,
	options: log.Options,
	location: runtime.Source_Code_Location,
) {

	backing: [1024]byte
	buf := strings.builder_from_bytes(backing[:])

	_level_header(options, &buf, level)
	_location_header(options, &buf, location)

	if .Thread_Id in options {
		fmt.sbprintf(&buf, "[{}] ", os.current_thread_id())
	}

	if ident != "" {
		fmt.sbprintf(&buf, "[%s] ", ident)
	}

	fmt.fprintf(h, "%s%s\n", strings.to_string(buf), text)
}

@(private = "file")
_level_header :: proc(opts: log.Options, str: ^strings.Builder, level: log.Level) {

	RESET :: ansi.CSI + ansi.RESET + ansi.SGR
	MAGENTA :: ansi.CSI + ansi.FG_MAGENTA + ansi.SGR
	GREEN :: ansi.CSI + ansi.FG_GREEN + ansi.SGR
	YELLOW :: ansi.CSI + ansi.FG_YELLOW + ansi.SGR
	RED :: ansi.CSI + ansi.FG_RED + ansi.SGR

	color := RESET
	switch level {
	case .Debug:
		color = MAGENTA
	case .Info:
		color = GREEN
	case .Warning:
		color = YELLOW
	case .Error, .Fatal:
		color = RED
	}

	if .Level in opts {
		if .Terminal_Color in opts {
			fmt.sbprint(str, color)
		}

		fmt.sbprint(str, log.Level_Headers[level])

		if .Terminal_Color in opts {
			fmt.sbprint(str, RESET)
		}
	}
}

@(private = "file")
_location_header :: proc(opts: log.Options, buf: ^strings.Builder, location := #caller_location) {

	RESET :: ansi.CSI + ansi.RESET + ansi.SGR
	DARK_GREY :: ansi.CSI + ansi.FG_BRIGHT_BLACK + ansi.SGR

	if log.Location_Header_Opts & opts == nil {
		return
	}

	if .Terminal_Color in opts {
		fmt.sbprint(buf, DARK_GREY)
	}

	fmt.sbprint(buf, "[")

	file := location.file_path
	if .Short_File_Path in opts {
		last := 0
		for r, i in location.file_path {
			if r == '/' {
				last = i + 1
			}
		}
		file = location.file_path[last:]
	}

	if log.Location_File_Opts & opts != nil {
		fmt.sbprint(buf, file)
	}

	if .Line in opts {
		if log.Location_File_Opts & opts != nil {
			fmt.sbprint(buf, ":")
		}
		fmt.sbprint(buf, location.line)
	}

	if .Procedure in opts {
		if (log.Location_File_Opts | {.Line}) & opts != nil {
			fmt.sbprint(buf, ":")
		}
		fmt.sbprintf(buf, "%s()", location.procedure)
	}

	fmt.sbprint(buf, "] ")

	if .Terminal_Color in opts {
		fmt.sbprint(buf, RESET)
	}
}
