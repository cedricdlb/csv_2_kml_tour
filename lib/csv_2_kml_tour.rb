

class Csv2KmlTour
#	attr_accessor :schedule_hash, :next_dates, :last_date
	def init
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
		#@bin_count = @bins.size
		@previous_bin = nil
		#@fraction_min = 0.9 # defaults may be overwritten in process_command_line
		#@fraction_max = 1.1 # defaults may be overwritten in process_command_line
		#@fraction_range = nil
		#@fraction_per_bin = nil

		# upper limits, <=:  -7%   -5%   -3%   +3%   +5%   +7%  > +7%   a fraction <= threshold[i] goes into bin[i] 
		@bin_thresholds = [0.93, 0.95, 0.97, 1.03, 1.05, 1.07] # Last bin fraction is everything above

		@nominal = 0
		@csv = nil
		@kml = nil
		@csv_column_names     = []
		@number_of_columns    = 0
		@report_progress_at   = 0.1 # next file fraction limit to report progress
		@reporting_increments = 0.1 # every this fraction of file, report progress
		@csv_file_size        = 0 # file size in bytes
		@csv_file_pos         = 0 # file position in bytes
		@progress_percent     = 0 # of parsing csv file
		@tour_current_time    = 0.00 # in seconds
		@tour_step_duration   = 0.25 # in seconds
	end

	def run
		init
		if(process_command_line &&
		   (additional_inits &&
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
	#	csv_2_kml_tour.rb <nominal_value> <input_csv_file_name.csv>
	#  example:
	#	csv_2_kml_tour.rb 7621 12MW_Voltage_B_On_7E_From_1757_To_853.csv
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
	def process_command_line
		were_inputs_ok = true
		@nominal = ARGV.shift.to_f
		csv_file_name = ARGV.shift

		unless File.exists?(csv_file_name) && File.file?(csv_file_name) && File.readable?(csv_file_name)
			puts "FAILURE: csv_file_name #{csv_file_name} does not exist, is not a proper file, or is not readable..."
			were_inputs_ok = false
		end

		#unless ("csv".equals(File.extname(csv_file_name)))
		unless (".csv" == File.extname(csv_file_name))
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
		
		if were_inputs_ok 
			@csv = File.open(csv_file_name, "r")
			@kml = File.open(output_file_name, "a+")
			# TODO: In the case of -a append to kml, I will need to position the
			#       write/insert pointer into the correct location before proceeding.
		end
		return were_inputs_ok 
	end

	def close_files
		@csv.close
		@kml.close
		true
	end

	def additional_inits
		# Determine bin size
		#@fraction_range = @fraction_max - @fraction_min
		#@fraction_per_bin = @fraction_range / (@bin_count - 1)
		@csv_file_size = @csv.size # file size      in bytes
		@csv_file_pos  = @csv.pos  # current offset in bytes, allowing me to report % progress
		@progress_percent = @csv_file_pos / @csv_file_size 
	end

	def parse_csv_headers
		was_process_successful = true
		# readlines from the csv file, skipping over all but the timestamp headers
		# TODO? ALT: instead of io.gets, use io.lines, which returns an enumerator to iterate over lines in io
		# TODO: how to have a one-line while without empty do end
		#while (csv_line = @csv.gets && !(csv_line =~ /^# timestamp,/)) do
		#	puts("DEBUG: csv header line: #{$_}")
		#end
		while (@csv.gets) do
		       	csv_line = $_.strip
		#	puts("DEBUG: csv header line: #{csv_line}")
			break if (csv_line =~ /^# timestamp,/)
		end
		unless csv_line
			# We're at the end of the file and the timestamp header was never found, which is an error...
			was_process_successful = false
			puts("ERROR: In parsing the csv file, the timestamp header was never found")
		else
			# must be on the timestamp line
			@csv_column_names = csv_line.split(",")
			@number_of_columns = @csv_column_names.size
			@previous_bin = Array.new(@number_of_columns)

			# Need to convert from column names to the names/ids of kml elements.
			# In the case of Saint John files, the power lines are names like STJ_1234
			# The node names are like oh_STJ_1234_Node, could also be ug_STJ_1234_Node
			# This makes it tied to processing oh or ug lines, but I may want to support
			# other elements, like transformers (xfmrBank), or the currents on lines not nodes, etc.
			# Generally, the Nodes have names like <type>_<ID>_Node, where
			#   <type> is one of fake, oh, ug, ocDevBank, regBank, swDevBank, xfmrBank, substation
			#   <ID> is: STJ_1234 for most oh, ug, ocDevBank, swDevBank,
			#            REG129, REG130 for regBank
			#            3-123456 for xfmrBank
			# TODO: figure out how to make the _Node part of the pattern optional,
			#       so that the <type>_ is stripped even if "_Node" is not in the name.
			@csv_column_names[0].gsub!(/^# /, '')
			@csv_column_names.each do |glm_name|
				glm_name.gsub!(/_Node/, '')
				glm_name.gsub!(/[^_]*_(.*)/, '\1')
			end
		end
		return was_process_successful
	end

	def write_kml_open_tour_tags
		@kml.puts()
		@kml.puts("  <!-- Add to top of kml file, in kml tag: xmlns:gx=\"http://www.google.com/kml/ext/2.2\" -->")
		@kml.puts()
		@kml.puts("  <gx:Tour>")
		@kml.puts("    <name>HeatMap #{@base_name}</name>")
		@kml.puts("    <gx:Playlist>")
		true
	end

	def write_kml_open_timestep_AnimatedUpdate_tags(timestamp)
		@kml.puts("      <gx:AnimatedUpdate>")
		@kml.puts("        <gx:delayedStart>#{@tour_current_time}</gx:delayedStart>") # unless (0 == @tour_current_time)
		@kml.puts("        <gx:duration>#{@tour_step_duration}</gx:duration>")
		@kml.puts("        <Update>")
		@kml.puts("          <!-- timestamp: #{timestamp} -->")
		@kml.puts("          <targetHref/>")
		@kml.puts("          <Change>")
		true
	end

	def write_kml_change_entry(id, level, animatedUpdate_is_open, timestamp)
		write_kml_open_timestep_AnimatedUpdate_tags(timestamp) unless animatedUpdate_is_open
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

	def parse_csv_data
		while (@csv.gets) do
		       	csv_line = $_.strip
			#puts("DEBUG: parsing csv_line #{csv_line}")
			animatedUpdate_is_open = false
			csv_columns = csv_line.split(",")
			csv_columns.each_with_index do |column_value, index|
				#puts("DEBUG: parsing csv column #{@csv_column_names[index]}: #{column_value}")
				if (0 == index)
					# TODO: Update a clock time element to show timestamp of heatmap data points #
				else
					fraction_of_nominal = column_value.to_f / @nominal
					#if (fraction_of_nominal <= @fraction_min)
					#	bin = @bins[0]
					#elsif (fraction_of_nominal >= @fraction_max)
					#	bin = @bins[-1]
					#else
					#	bin = @bins[((fraction_of_nominal - @fraction_min) / @fraction_per_bin).round]
					#end
					bin = nil
					@bin_thresholds.each_with_index do |threshold, bin_index|
						if (fraction_of_nominal <= threshold)
							bin = @bins[bin_index]
							break
						end
					end
					bin = @bins[-1] unless bin

					if (bin != @previous_bin[index])
						@previous_bin[index] = bin
						write_kml_change_entry(@csv_column_names[index], bin, animatedUpdate_is_open, csv_columns[0])
						animatedUpdate_is_open = true unless animatedUpdate_is_open 
					end
				end
			end
			write_kml_close_timestep_AnimatedUpdate_tags if animatedUpdate_is_open
			@tour_current_time += @tour_step_duration

			check_on_progress
		end
		true
	end

	def check_on_progress
		@csv_file_pos = @csv.pos
		@progress_percent = @csv_file_pos / @csv_file_size 
		if (@progress_percent >= @report_progress_at)
			@report_progress_at += @reporting_increments
			puts sprintf("%3d%% of csv file processed", @progress_percent*100)
		end
	end



end
