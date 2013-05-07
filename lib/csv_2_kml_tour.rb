
class Csv2KmlTour
#	attr_accessor :schedule_hash, :next_dates, :last_date
	def initialize
		@bins = [
			#"Level_neg_12", # Blue
			#"Level_neg_11", # Blue_Azure
			#"Level_neg_10", # Azure_Blue
			#"Level_neg_09", # Azure
			#"Level_neg_08", # Azure_Cyan
			#"Level_neg_07", # Cyan_Azure
			#"Level_neg_06", # Cyan
			#"Level_neg_05", # Cyan_SpringGreen
			#"Level_neg_04", # SpringGreen_Cyan
			#"Level_neg_03", # SpringGreen
			#"Level_neg_02", # SpringGreen_Green
			#"Level_neg_01", # Green_SpringGreen
			#"Level_ctr_00", # Green
			#"Level_pos_01", # Green_Chartreuse
			#"Level_pos_02", # Chartreuse_Green
			#"Level_pos_03", # Chartreuse
			#"Level_pos_04", # Chartreuse_Yellow
			#"Level_pos_05", # Yellow_Chartreuse
			#"Level_pos_06", # Yellow
			#"Level_pos_07", # Yellow_Orange
			#"Level_pos_08", # Orange_Yellow
			#"Level_pos_09", # Orange
			#"Level_pos_10", # Orange_Red
			#"Level_pos_11", # Red_Orange
			#"Level_pos_12", # Red
			"Level_neg_03", # Blue
			"Level_neg_02", # Azure
			"Level_neg_01", # Cyan
			"Level_ctr_00", # Green
			"Level_pos_01", # Yellow
			"Level_pos_02", # Orange
			"Level_pos_03", # Red
		]
		@previous_bins = []

		# upper limits, <=:  -7%   -5%   -3%   +3%   +5%   +7%  > +7%   a fraction <= threshold[i] goes into bin[i] 
		@bin_thresholds = [0.93, 0.95, 0.97, 1.03, 1.05, 1.07] # Last bin fraction is everything above

		@nominal = 0
		@csv = nil
		@kml = nil
		@total_chars_read        = 0
		@number_of_timestamps    = 0
		@csv_column_names        = []
		@fraction_totals         = []
		@fraction_highs          = []
		@fraction_lows           = []
		@times_above_max_allowed = []
		@times_below_min_allowed = []
		@timestamps_starts_above = []
		@timestamps_starts_below = []
		@max_allowed_limit       = 1.05
		@min_allowed_limit       = 0.95
		@first_timestamp         = nil
		@previous_timestamp      = nil
		@current_timestamp       = nil
		@elapsed_seconds         = 0
		@tour_current_time       = 0.00 # in seconds
		@tour_step_duration      = 0.02 # in seconds
	end

	def run
		initialize
		if(process_command_line &&
		   (setup_progress_status &&
		    parse_csv_headers &&
		    write_kml_open_tour_tags &&
		    parse_csv_data &&
		    write_kml_close_tour_tags) and
		   close_files)
			puts "INFO: csv_2_kml_tour run successfully"
		else
			puts "INFO: csv_2_kml_tour run experienced an error"
		end
	end
	
	# Usage: 
	#	ruby bin\csv_2_kml_tour.rb <nominal_value> <input_csv_file_name.csv>
	#  example:
	#	ruby bin\csv_2_kml_tour.rb 7621 12MW_Voltage_B_On_7E_From_1757_To_853.csv
	# OUTPUT: writes out file changes.<input_csv_file_name>.kml, e.g.:
	#	           changes.12MW_Voltage_B_On_7E_From_1757_To_853.kml
	#
	# FUTURE Usage:
	#	csv_2_kml_tour.rb <nominal_value> <input_csv_file_name_csv> [-n <min_fraction>] [-x <max_fraction>] [-a <appending_kml> | -o <output_filename>]
	#
	#  example:
	#	csv_2_kml_tour.rb 7621 -o oh_lines.12MW_Voltage_B_On_7E_From_1757_To_853.kml -n 0.9 -x 1.1 12MW_Voltage_B_On_7E_From_1757_To_853.csv
	# OUTPUT: writes out file     oh_lines.12MW_Voltage_B_On_7E_From_1757_To_853.kml
	#
	#  example:
	#	csv_2_kml_tour.rb 7621 -a oh_lines.color_coded.kml -n 0.9 -x 1.1 12MW_Voltage_B_On_7E_From_1757_To_853.csv
	# OUTPUT: appended to end of kml file oh_lines.color_coded.kml just before closing </Document> </kml> tags
	#
	# ASSUMPTION: the csv has a set of timestamps one for each consecutive minute, only one per minute, not skipping minutes.
	# FUTURE: (automatically or by flag) handle gaps in timestamps by adjusting AnimatedUpdate delayedStart times accordingly.
	# TODO?:  Add parameters to specify a start and end range of the data set to actually analyze? (Bob's suggestion)
	def process_command_line
		were_inputs_ok = true
		@nominal = ARGV.shift.to_f
		csv_file_name = ARGV.shift

		unless File.exists?(csv_file_name) && File.file?(csv_file_name) && File.readable?(csv_file_name)
			puts "FAILURE: csv_file_name #{csv_file_name} does not exist, is not a proper file, or is not readable..."
			were_inputs_ok = false
		end

		#unless "csv".equals(File.extname(csv_file_name))
		unless ".csv" == File.extname(csv_file_name)
			puts "FAILURE: csv_file_name #{csv_file_name} extension (#{File.extname(csv_file_name)}) is not '.csv'."
			were_inputs_ok = false
		end

		# TODO: Allow for cmd line flag [-o <output_filename>] to set output_file_name
		# TODO: Allow for cmd line flag [-a <appending_kml>] to specify a kml file into which
		#       to append the output, just before closing </Document> </kml> tags
		# generate default output_file_name based on the csv_file_name base
	#	unless output_file_name
			@base_name = File.basename(csv_file_name, ".*")
			output_file_name = File.join(File.dirname(csv_file_name), "changes.#{@base_name}.kml")
			puts "INFO: Output KML Tour will be written to file #{output_file_name}"
	#	end

		# TODO?: Allow for cmd line flag [-n <min_fraction>] to set @fraction_min
		# TODO?: Allow for cmd line flag [-x <max_fraction>] to set @fraction_max
		# TODO: Allow for cmd line flags to set fraction levels as an array of +/- variances of nominal
		#	e.g. (not sure of format): [-l "3%, 5%, 7%"]
		#	would set up 7 bins: ...-7%...-5%...-3%...+3%...+5%...+7%...
		#	                     bin   bin   bin   bin   bin   bin   bin
		# TODO: Allow for cmd line flags to set duration between timestamps (@tour_step_duration), i.e. [-s 0.2]
		
		if were_inputs_ok 
			@csv = File.open(csv_file_name, "r")
			@kml = File.open(output_file_name, "a+")
			# TODO: In the case of -a append to kml, I will need to position the
			#       write/insert pointer into the correct location before proceeding.
		end
		were_inputs_ok 
	end

	def close_files
		@csv.close
		@kml.close
		true
	end

	def setup_progress_status
		@progress_status = ProgressStatus.new(@csv.size, @csv.pos)
	end

	def parse_csv_headers
		was_process_successful = true
		# readlines from the csv file, skipping over all but the timestamp headers
		# TODO? ALT: use io.lines instead of io.gets, to process lines with an iterator
		while (@csv.gets) do
			@total_chars_read += $LAST_READ_LINE.size
			break if $LAST_READ_LINE =~ /^# timestamp,/
		end

		csv_line = $LAST_READ_LINE
		if csv_line
			# must be on the timestamp line
			@csv_column_names  = csv_line.strip.split(",")

			# Need to convert from column names to the names/ids of kml elements.
			# In the case of Saint John files, the power lines are names like STJ_1234
			# The node names are like oh_STJ_1234_Node
			# Generally, the Nodes have names like <type>_<ID>_Node, where
			#   <type> is one of fake, oh, ug, ocDevBank, regBank, swDevBank, xfmrBank, substation
			#   <ID> is: STJ_1234 for most oh, ug, ocDevBank, swDevBank,
			#            REG129, REG130 for regBank
			#            3-123456 for xfmrBank
			@csv_column_names[0].gsub!(/^# /, '')
			@csv_column_names.each do |glm_name|
				glm_name.gsub!(/_Node/, '')
				glm_name.gsub!(/[^_]*_(.*)/, '\1')
			end
		else
			# File is empty or the timestamp header was never found, which is an error...
			was_process_successful = false
			puts("ERROR: In parsing the csv file, the timestamp header was never found")
		end
		was_process_successful
	end

	TIMESTAMP_INDEX = 0
	def parse_csv_data
		count_of_data_rows = 0
		# TODO? ALT: use io.lines instead of io.gets, to process lines with an iterator
		while (@csv.gets) do
			csv_line = $LAST_READ_LINE
			count_of_data_rows += 1
#			puts("DEBUG: data_row #{count_of_data_rows} parsing csv line: #{csv_line}")
			@animatedUpdate_is_open = false # gets set to true if any of this row's data points cause an update
			csv_line.split(",").each_with_index do |column_value, index|
#				puts("DEBUG: parsing csv column index #{index}: '#{column_value}'")
				TIMESTAMP_INDEX == index ? process_timestamp(column_value) :
							   process_data_point(column_value, index)
			end
			write_kml_close_timestep_AnimatedUpdate_tags if @animatedUpdate_is_open
			@tour_current_time += @tour_step_duration
			@total_chars_read += csv_line.size
			@progress_status.report_progress(@total_chars_read)
			#@progress_status.report_progress(@csv.pos)
			# NOTE: Can't use @csv.pos as it affects the lines subsequently read.
			#       The effect is that on the next io.gets, the date is left out.
			#       On each subsequent io.gets, the data is left out except for one additional character:
			#       DEBUG: data_row  1 parsing csv line: 2010-03-27 00:00:00 PDT,7721.584034...
			#       DEBUG: data_row  2 parsing csv line:  00:01:00 PDT,7720.945366,7721.2328...
			#       DEBUG: data_row  3 parsing csv line: 7 00:02:00 PDT,7720.207934,7720.493...
			#       DEBUG: data_row  4 parsing csv line: 27 00:03:00 PDT,7719.788189,7720.07...
			#       DEBUG: data_row  5 parsing csv line: -27 00:04:00 PDT,7719.316053,7719.5...
			#       DEBUG: data_row  6 parsing csv line: 3-27 00:05:00 PDT,7719.868483,7720....
			#       DEBUG: data_row  7 parsing csv line: 03-27 00:06:00 PDT,7719.629886,7719...
			#       DEBUG: data_row  8 parsing csv line: -03-27 00:07:00 PDT,7619.629886,761...
			#       DEBUG: data_row  9 parsing csv line: 0-03-27 00:08:00 PDT,7519.629886,75...
			#       DEBUG: data_row 10 parsing csv line: 10-03-27 00:09:00 PDT,7319.629886,7...
			#       DEBUG: data_row 11 parsing csv line: 010-03-27 00:10:00 PDT,7219.629886,...
		end

		# TODO: Calculate averages from totals
		# TODO: Calculate percent of time spent above max or below min limits allowed
		true
	end

	def process_timestamp(column_value)
		@current_timestamp = DateTime.strptime(column_value, "%F %T %Z")
		@first_timestamp    ||= @current_timestamp
		@previous_timestamp ||= @current_timestamp
		@elapsed_seconds = ((@current_timestamp - @previous_timestamp) * 24 * 60 * 60).to_i # DateTime diff is in days
		@previous_timestamp = @current_timestamp
		# TODO: Update a clock time element to show timestamp of heatmap data points
	end

	def process_data_point(column_value, index)
		fraction_of_nominal = column_value.to_f / @nominal
		track_fraction_totals_highs_lows_and_times(fraction_of_nominal, index)
		determine_bin_for_fraction_and_record_if_changed(fraction_of_nominal, index)
	end

	# Track totals (for averages), highs, lows, times above/below limits
	def track_fraction_totals_highs_lows_and_times(fraction_of_nominal, index)
		@fraction_totals[index] ||= 0
		@fraction_totals[index] += fraction_of_nominal
		@times_below_min_allowed[index] ||= 0
		@times_above_max_allowed[index] ||= 0
		@times_below_min_allowed[index] += @elapsed_seconds if @timestamps_starts_below[index]
		@times_above_max_allowed[index] += @elapsed_seconds if @timestamps_starts_above[index]

		if fraction_of_nominal > @max_allowed_limit
			@fraction_highs[index] ||= fraction_of_nominal
			@fraction_highs[index]   = fraction_of_nominal if fraction_of_nominal > @fraction_highs[index]
			@timestamps_starts_above[index] ||= @current_timestamp
			@timestamps_starts_below[index] &&= nil
		elsif fraction_of_nominal < @min_allowed_limit
			@fraction_lows[index]  ||= fraction_of_nominal
			@fraction_lows[index]    = fraction_of_nominal if fraction_of_nominal < @fraction_lows[index]
			@timestamps_starts_above[index] &&= nil
			@timestamps_starts_below[index] ||= @current_timestamp unless @timestamps_starts_below[index]
		else
			@timestamps_starts_below[index] &&= nil
			@timestamps_starts_above[index] &&= nil
		end
	end

	def determine_bin_for_fraction_and_record_if_changed(fraction_of_nominal, index)
		bin = nil
		@bin_thresholds.each_with_index do |threshold, bin_index|
			if fraction_of_nominal <= threshold
				bin = @bins[bin_index]
				break
			end
		end
		bin = @bins[-1] unless bin

		if bin != @previous_bins[index]
			@previous_bins[index] = bin
			write_kml_change_entry(@csv_column_names[index], bin)
			@animatedUpdate_is_open ||= true
		end
	end

	def write_kml_open_tour_tags
		# TODO: Show a legend of the levels and their threshold value ranges
		@kml.puts()
		@kml.puts("  <!-- Add to top of kml file, in kml tag: xmlns:gx=\"http://www.google.com/kml/ext/2.2\" -->")
		@kml.puts()
		@kml.puts("  <gx:Tour>")
		@kml.puts("    <name>HeatMap #{@base_name}</name>")
		@kml.puts("    <gx:Playlist>")
		true
	end

	def write_kml_open_timestep_AnimatedUpdate_tags
		@kml.puts("      <gx:AnimatedUpdate>")
		@kml.puts("        <gx:delayedStart>#{@tour_current_time}</gx:delayedStart>")
		@kml.puts("        <gx:duration>#{@tour_step_duration}</gx:duration>")
		@kml.puts("        <Update>")
		@kml.puts("          <!-- timestamp: #{@current_timestamp.to_s} -->")
		@kml.puts("          <targetHref/>")
		@kml.puts("          <Change>")
		true
	end

	def write_kml_change_entry(id, level)
		write_kml_open_timestep_AnimatedUpdate_tags unless @animatedUpdate_is_open
		@kml.puts("            <Placemark targetId=\"#{id}\"> <styleUrl>##{level}</styleUrl> </Placemark>")
		true
	end

	def write_kml_close_timestep_AnimatedUpdate_tags
		@kml.puts("          </Change>")
		@kml.puts("        </Update>")
		@kml.puts("      </gx:AnimatedUpdate>")
		true
	end

	def write_kml_close_tour_tags
		@kml.puts()
		@kml.puts("       <!-- Wait for the animation to complete (see the touring")
		@kml.puts("            tutorial for an explanation of how AnimatedUpdate's")
		@kml.puts("            duration isn't enough to guarantee this). -->")
		@kml.puts("      <gx:Wait>")
		@kml.puts("        <gx:duration>#{@tour_current_time}</gx:duration>")
		@kml.puts("      </gx:Wait>")
		@kml.puts("    </gx:Playlist>")
		@kml.puts("  </gx:Tour>")
		true
	end
end
