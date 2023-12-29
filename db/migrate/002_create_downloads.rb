class CreateDownloads < ActiveRecord::Migration[6.1]
  def change
    create_table :downloads do |t|
      t.integer :archive_id
      t.string :filename
      t.string :url
      t.string :status
      t.integer :size
      t.timestamps null: false
    end
  end
end
