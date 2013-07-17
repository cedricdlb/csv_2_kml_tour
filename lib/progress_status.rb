class ProgressStatus
	attr_accessor :file_size, :threshold_for_new_progress_report, :reporting_increment
	attr_reader   :file_pos, :progress_percent

	DEFAULT_REPORT_EVERY_X_PERCENT = 10.0 # report on progress every 10% of file read

	def initialize(size)
		@file_size = size
		@file_pos = 0
		@reporting_increment = DEFAULT_REPORT_EVERY_X_PERCENT
		@threshold_for_new_progress_report = @reporting_increment
	end

	def file_pos=(file_position)
		@file_pos = file_position.to_f
		@progress_percent = file_pos * 100.0 / file_size
	end

	def update_file_position(line)
		file_pos += line.size
	end

	#def report_progress(file_position)
	#	self.file_pos = file_position if file_position 
	def report_progress(line)
		update_file_position(line)
		if progress_percent >= threshold_for_new_progress_report
			increment_to_next_reporting_threshold
			puts sprintf("%3d%% of csv file processed", progress_percent)
		end
	end

	def increment_to_next_reporting_threshold
		threshold_for_new_progress_report += reporting_increment until threshold_for_new_progress_report > progress_percent
	end

end
