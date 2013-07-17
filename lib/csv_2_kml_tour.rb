
class Csv2KmlTour
#	attr_accessor :schedule_hash, :next_dates, :last_date
	def initialize
		@nominal = 0
		@csv = nil
		@kml = nil
		@summary = nil
		@column_aggregators      = []
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
		    output_aggregate_info &&
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
			@summary = File.open(output_file_name, "a+")
			# TODO: In the case of -a append to kml, I will need to position the
			#       write/insert pointer into the correct location before proceeding.
		end
		were_inputs_ok 
	end

	def close_files
		@csv.close
		@kml.close
		@summary.close
		true
	end

	def setup_progress_status
		@progress_status = ProgressStatus.new(@csv.size)
	end

	def parse_csv_headers
		was_process_successful = true
		# readlines from the csv file, skipping over all but the timestamp headers
		# TODO? ALT: use io.lines instead of io.gets, to process lines with an iterator
		while (@csv.gets) do
			@progress_status.report_progress($LAST_READ_LINE)
			break if $LAST_READ_LINE =~ /^# timestamp,/
		end

		csv_line = $LAST_READ_LINE
		if csv_line
			# Must be on the timestamp line
			#
			# Need to convert from column names to the names/ids of kml elements.
			# In the case of Saint John files, the power lines are names like STJ_1234
			# The node names are like oh_STJ_1234_Node
			# Generally, the Nodes have names like <type>_<ID>_Node, where
			#   <type> is one of fake, oh, ug, ocDevBank, regBank, swDevBank, xfmrBank, substation
			#   <ID> is: STJ_1234 for most oh, ug, ocDevBank, swDevBank,
			#            REG129, REG130 for regBank
			#            3-123456 for xfmrBank
			csv_column_names = csv_line.strip.split(",")
			csv_column_names[0].gsub!(/^# /, '')
			csv_column_names.each do |glm_name|
				glm_name.gsub!(/_Node/, '')
				glm_name.gsub!(/[^_]*_(.*)/, '\1')
				@column_aggregators << ColumnAggregator.new(glm_name, @nominal)
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
			@progress_status.report_progress(csv_line)
		end

		# TODO: Calculate percent of time spent above max or below min limits allowed
		true
	end

	def output_aggregate_info
		# TODO: Calculate averages from totals
		@column_aggregators.each do |column_aggregator|
		end
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
		new_bin = @column_aggregators[index].add_value(column_value, @elapsed_seconds)
		if new_bin
			write_kml_change_entry(@column_aggregators[index].column_name, new_bin)
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
