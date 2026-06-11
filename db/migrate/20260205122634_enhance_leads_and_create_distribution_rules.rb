class EnhanceLeadsAndCreateDistributionRules < ActiveRecord::Migration[7.1]
  def change
    # 1. Create Distribution Rules FIRST to use as foreign key
    create_table :distribution_rules do |t|
      t.string :name, null: false
      t.integer :business_type, default: 0 # 0: venda, 1: locacao, 2: ambos
      t.boolean :source_meta, default: false
      t.boolean :source_webhook, default: false
      t.boolean :source_portal, default: false
      t.jsonb :meta_forms, default: []
      t.jsonb :webhook_tags, default: []
      t.jsonb :custom_filters, default: []
      t.integer :distribution_mode, default: 0 # 0: rotary, 1: performance, 2: shark_tank
      t.boolean :pocket_active, default: false
      t.integer :pocket_time, default: 30
      t.boolean :represamento_active, default: false
      t.jsonb :represamento_schedule, default: {}
      t.boolean :active, default: true
      t.decimal :min_price, precision: 15, scale: 2
      t.decimal :max_price, precision: 15, scale: 2

      t.timestamps
    end

    # 2. Enhance Leads table
    change_table :leads do |t|
      t.string :client_name
      t.string :client_email
      t.string :client_phone
      t.string :client_c2s_id
      t.string :agent_name
      t.string :agent_email
      t.string :agent_phone
      t.string :agent_c2s_id
      t.string :event_name
      t.string :origin
      t.string :product
      t.jsonb :other_information, default: {}
      t.jsonb :custom_answers, default: []
      t.references :distribution_rule, foreign_key: true
      t.references :admin_user, foreign_key: true
    end

    add_index :leads, :client_c2s_id
    add_index :leads, :origin

    # 3. Create Distribution Rule Agents
    create_table :distribution_rule_agents do |t|
      t.references :distribution_rule, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.integer :weight, default: 1
      t.datetime :last_lead_received_at
      t.integer :position

      t.timestamps
    end
    add_index :distribution_rule_agents, [:distribution_rule_id, :admin_user_id], unique: true, name: 'idx_dist_rule_agents_on_rule_and_admin'

    # 4. Create Lead Activities
    create_table :lead_activities do |t|
      t.references :lead, null: false, foreign_key: true
      t.string :kind
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # 5. Create Meta Integration Tables
    create_table :user_meta_integrations do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.string :access_token
      t.string :facebook_user_id
      t.string :name
      t.string :email
      t.datetime :token_expires_at

      t.timestamps
    end

    create_table :meta_facebook_pages do |t|
      t.references :user_meta_integration, null: false, foreign_key: true
      t.string :page_id
      t.string :name
      t.string :access_token
      t.boolean :active, default: true
      t.string :category

      t.timestamps
    end
    add_index :meta_facebook_pages, :page_id, unique: true

    create_table :meta_lead_forms do |t|
      t.references :meta_facebook_page, null: false, foreign_key: true
      t.string :form_id
      t.string :name
      t.boolean :active, default: true
      t.datetime :facebook_created_at

      t.timestamps
    end
    add_index :meta_lead_forms, :form_id, unique: true
  end
end
