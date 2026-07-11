require 'json'
require 'fileutils'
require 'securerandom'
require 'date'

module Store
  APP_ROOT = File.expand_path('..', __dir__)

  class << self
    attr_writer :data_root

    def data_root
      @data_root ||= ENV.fetch('DATA_DIR', File.join(APP_ROOT, 'data'))
    end
  end
end

require 'store/json_store'
require 'store/formattable'
require 'store/service'
# require 'store/business'
# require 'store/client'
# require 'store/invoice'
# require 'store/timesheet_period'
