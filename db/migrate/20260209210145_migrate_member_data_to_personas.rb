class MigrateMemberDataToPersonas < ActiveRecord::Migration[8.1]
  def up
    # Create Persona records from unique Member RUNs
    # For duplicate RUNs, take the first member's data
    execute <<~SQL
      INSERT INTO personas (first_name, last_name, run, phone, email, verification_status, created_at, updated_at)
      SELECT m.first_name, m.last_name, m.run, m.phone, m.email, 'verified', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM members m
      INNER JOIN (
        SELECT MIN(id) AS id FROM members WHERE run IS NOT NULL AND run != '' GROUP BY run
      ) dedup ON m.id = dedup.id
    SQL

    # Link members to their persona by RUN
    execute <<~SQL
      UPDATE members
      SET persona_id = (
        SELECT personas.id FROM personas WHERE personas.run = members.run
      )
      WHERE members.run IS NOT NULL AND members.run != ''
    SQL

    # Link users to persona via their member
    execute <<~SQL
      UPDATE users
      SET persona_id = (
        SELECT members.persona_id FROM members WHERE members.user_id = users.id LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM members WHERE members.user_id = users.id AND members.persona_id IS NOT NULL
      )
    SQL
  end

  def down
    execute "UPDATE users SET persona_id = NULL"
    execute "UPDATE members SET persona_id = NULL"
    execute "DELETE FROM personas"
  end
end
