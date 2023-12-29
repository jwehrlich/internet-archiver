class CreateArchives < ActiveRecord::Migration[6.1]
  def change
    create_table :archives do |t|
      t.string :key
      t.string :status
      t.integer :priority
      t.timestamps null: false
    end
  end
end
