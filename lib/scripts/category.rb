class CategoryScaffold
  BASE_COMMAND_GENERATE = "rails g scaffold"
  BASE_COMMAND_DESTROY = "rails d scaffold"
  CLASS_NAME = "Category"
  COMMAND_OPTIONS = "--skip-migration --force"
  #COMMAND_OPTIONS = ""

  FIELDS = %w[name:string]

  def generate_command
    @command = "#{BASE_COMMAND_GENERATE} #{CLASS_NAME} #{FIELDS.join(" ")} #{COMMAND_OPTIONS}"
  end

  def destroy_command
    @command = "#{BASE_COMMAND_DESTROY} #{CLASS_NAME}"
  end

  # If you ever want to print or access the command outside the class:
  attr_reader :command
end
