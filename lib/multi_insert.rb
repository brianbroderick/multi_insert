# frozen_string_literal: true

class MultiInsert
  attr_reader :records, :opts, :now, :returning

  def initialize(records, opts = {})
    @records = records.map(&:with_indifferent_access)
    @opts = opts.with_indifferent_access
    @now = ::Time.zone.now
    @returning = @opts.fetch(:returning, "")
    raise ArgumentError, "Must provide a model" unless self.opts[:model].present?
  end

  def self.call(*args)
    new(*args).call
  end 

  def call
    return false unless records.present?

    with_timestamps!
    inject_attribute_names_into_manager!
    write_batches!

    results.empty? ? records : results
  rescue => exception
    notify(exception, { records: records, opts: opts.inspect }, shard)
  ensure
    # To aid garbage collection    
    @records.clear if @records.present?
  end

  def with_timestamps!
    records.each do |record|
      record[:created_at] = now if record[:created_at].nil?
      record[:updated_at] = now if record[:updated_at].nil?
    end
  end

  def shard
    @shard ||= opts[:shard]
  end

  def results
    @results ||= []
  end

  def model
    @model ||= opts[:model]
  end

  def batch_size
    @batch_size ||= opts.fetch(:batch_size, 0)
  end

  def batches
    return 0 if batch_size.zero?

    (records.length.to_f / batch_size.to_f).ceil
  end

  def ignore_attributes
    @ignore_attributes ||= opts.fetch(:ignore_attributes, [])
  end

  def insert_manager
    if rails4?
      ::Arel::InsertManager.new(::ActiveRecord::Base)
    elsif rails5?
      ::Arel::InsertManager.new
    else
      raise("ActiveRecord versions 4 or 5 are supported.")
    end    
  end  

  def manager
    @manager ||= insert_manager.tap do |manager|
      manager.into ::Arel::Table.new(model.table_name)
    end
  end

  def table
    @table ||= ::Arel::Table.new(model)
  end

  def attribute_names
    return @attribute_names if @attribute_names.present?

    @attribute_names = model.attribute_names.dup
    ::Array.wrap(ignore_attributes).each do |attribute|
      @attribute_names.delete(attribute)
    end

    @attribute_names
  end

  def inject_attribute_names_into_manager!
    return @injected if @injected.present?
    attribute_names.each { |k| manager.columns << table[k] }
    @injected = true
  end

  def write_batches!
    if batches.zero?
      write!(records)
    else
      1.upto(batches) { write!(records.pop(batch_size)) }
    end
  end

  def write!(subset)
    return :blank if subset.blank?

    values = get_values(subset)
    response = run_insert!(build_sql(values))
    zipper_returning_ids(subset, response)
  end

  def get_values(subset)
    arr = []
    subset.each do |record|
      tmp_ary = []
      attribute_names.each { |c| tmp_ary << model.sanitize(record[c]) }
      arr << "(#{tmp_ary.join(",")})"
    end
    arr
  end

  def zipper_returning_ids(subset, response)
    return :nothing_returned if response.ntuples.zero?

    response.each_with_index do |hash, index|
      results << subset[index].merge!(hash).with_indifferent_access
    end
  end

  def returning_ids_text
    returning.blank? ? "" : "returning #{returning}"
  end

  def build_sql(sql_values)
    "#{manager.to_sql} VALUES #{sql_values.join(",")} #{opts.fetch(:sql_append, "")} #{returning_ids_text}"
  end

  def run_insert!(sql)
    if shard.nil?
      ::ActiveRecord::Base.connection_pool.with_connection { |conn| conn.execute(sql) }
    else
      ::Octopus.using(shard) do
        ::ActiveRecord::Base.connection_pool.with_connection { |conn| conn.execute(sql) }
      end
    end
  end

  def notify(exception, parameters = nil, shard = nil) # rubocop:disable Rails/Output
    pp({ name: self.class,
         exception_class: exception.class,
         exception: exception.message,
         backtrace: exception.backtrace,
         shard: shard,
         parameters: parameters }) 
    raise "ErrorLog: Error in test" if defined?(Rails) && Rails.env == "test"
  end  

  def rails4?
    ::ActiveRecord::VERSION::MAJOR == 4
  end

  def rails5?
    ::ActiveRecord::VERSION::MAJOR == 5
  end  
end
