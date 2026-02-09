json.extract! board_member, :id, :member_id, :position, :start_date, :end_date, :active, :created_at, :updated_at
json.url admin_board_member_url(board_member, format: :json)
