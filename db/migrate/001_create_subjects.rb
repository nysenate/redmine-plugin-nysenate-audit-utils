# frozen_string_literal: true

class CreateSubjects < ActiveRecord::Migration[6.1]
  def change
    create_table :subjects do |t|
      t.string :subject_type, limit: 50, null: false
      t.string :subject_id, limit: 100, null: false
      t.string :name, limit: 200, null: false
      t.string :email, limit: 200
      t.string :phone, limit: 50
      t.string :uid, limit: 100
      t.string :location, limit: 200
      t.string :status, limit: 50, null: false, default: 'Active'
      t.timestamps null: false

      t.index [:subject_type, :subject_id], unique: true, name: 'idx_subject_type_id'
      t.index :name, name: 'idx_subject_name'
      t.index :status, name: 'idx_subject_status'
    end
  end
end
