Class ColumnAggregator
	@@bins = [
		"Level_neg_03", # Blue
		"Level_neg_02", # Azure
		"Level_neg_01", # Cyan
		"Level_ctr_00", # Green
		"Level_pos_01", # Yellow
		"Level_pos_02", # Orange
		"Level_pos_03", # Red
	]
	# upper limits, <=:  -7%   -5%   -3%   +3%   +5%   +7%  > +7%   a fraction <= threshold[i] goes into bin[i] 
	@@bin_thresholds = [0.93, 0.95, 0.97, 1.03, 1.05, 1.07] # Last bin fraction is everything above

	attr_accessor :column_name, :bin, :previous_bin, :row_count
	attr_writer   :bins, :bin_thresholds
	attr_accessor :nominal, :fraction_of_nominal, :fractions_total, :fraction_high, :fraction_low 
	attr_accessor :time_to_record, :time_below_min_allowed, :time_above_max_allowed
	attr_accessor :max_allowed_limit, :min_allowed_limit
	#attr_accessor :timestamp_starts_below, :timestamp_starts_above
	# NOTE: for the values of time_to_record, there isn't a handy Ruby equivalent to enum in C/Java
	# TIME_TO_RECORD_VALUES = [:none, :time_below_min, :time_above_max]

	def initialize(column_name, nominal)
		@column_name = column_name
		@nominal     = nominal
		@row_count              = 0
		@fractions_total        = 0
		@max_allowed_limit      = 1.05
		@min_allowed_limit      = 0.95
		@time_below_min_allowed = 0
		@time_above_max_allowed = 0
		@time_to_record         = :none
	end

	def bins
		@bins || @@bins
	end

	def bin_thresholds
		@bin_thresholds || @@bin_thresholds
	end

	def add_value(column_value, elapsed_seconds)
		fraction_of_nominal = column_value.to_f / nominal
		track_fraction_totals_highs_lows_and_times(fraction_of_nominal, elapsed_seconds)
		determine_new_bin
	end

	# Track totals (for averages), highs, lows, times above/below limits
	def track_fraction_totals_highs_lows_and_times(fraction_of_nominal, elapsed_seconds)
		fractions_total += fraction_of_nominal
		time_below_min_allowed += elapsed_seconds if :time_below_min == time_to_record
		time_above_max_allowed += elapsed_seconds if :time_above_max == time_to_record

		if fraction_of_nominal > max_allowed_limit
			time_to_record = :time_above_max
			fraction_high ||= fraction_of_nominal
			fraction_high   = fraction_of_nominal if fraction_of_nominal > fraction_high
		elsif fraction_of_nominal < min_allowed_limit
			time_to_record = :time_below_min
			fraction_low  ||= fraction_of_nominal
			fraction_low    = fraction_of_nominal if fraction_of_nominal < fraction_low
		else
			time_to_record = :none
		end
	end

	def determine_new_bin
		new_bin = nil
		bin_thresholds.each_with_index do |threshold, bin_index|
			if fraction_of_nominal <= threshold
				new_bin = bins[bin_index]
				break
			end
		end
		new_bin = bins[-1] unless new_bin

		if new_bin != previous_bin
			previous_bin = new_bin
			new_bin
		else
			nil
		end
	end

	def average_fraction
		fractions_total / row_count
	end


end
