class ListingScaffold
  BASE_COMMAND_GENERATE = "rails g scaffold"
  BASE_COMMAND_DESTROY = "rails d scaffold"
  CLASS_NAME = "Listing"
  COMMAND_OPTIONS = "--skip-fixture --skip-migration --force"
  #COMMAND_OPTIONS = ""

  FIELDS = %w[name:string description:text price:decimal active:boolean user:references].freeze

  def generate_command
    @command = "#{BASE_COMMAND_GENERATE} #{CLASS_NAME} #{FIELDS.join(" ")} #{COMMAND_OPTIONS}"
  end

  def destroy_command
    @command = "#{BASE_COMMAND_DESTROY} #{CLASS_NAME}"
  end

  # If you ever want to print or access the command outside the class:
  attr_reader :command
end
