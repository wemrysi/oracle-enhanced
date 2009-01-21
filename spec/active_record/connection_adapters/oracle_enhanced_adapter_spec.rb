require File.dirname(__FILE__) + '/../../spec_helper.rb'

describe "OracleEnhancedAdapter establish connection" do
  
  it "should connect to database" do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  it "should connect to database as SYSDBA" do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "sys",
                                            :password => "manager",
                                            :privilege => :SYSDBA)
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  it "should connect to database using different schema" do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr",
                                            :schema => "sys")
    ActiveRecord::Base.connection.should_not be_nil
    ActiveRecord::Base.connection.select_one("SELECT sys_context('userenv', 'current_schema') schema FROM DUAL")["schema"].should == 'SYS'
  end
  
end

describe "OracleEnhancedAdapter schema dump" do
  
  before(:all) do
    @old_conn = ActiveRecord::Base.oracle_connection(
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @old_conn.class.should == ActiveRecord::ConnectionAdapters::OracleAdapter
    @new_conn = ActiveRecord::Base.oracle_enhanced_connection(
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @new_conn.class.should == ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter
  end

  it "should return the same tables list as original oracle adapter" do
    @new_conn.tables.should == @old_conn.tables
  end

  it "should return the same index list as original oracle adapter" do
    @new_conn.indexes('employees').should == @old_conn.indexes('employees')
  end

  it "should return the same pk_and_sequence_for as original oracle adapter" do
    @new_conn.tables.each do |t|
      @new_conn.pk_and_sequence_for(t).should == @old_conn.pk_and_sequence_for(t)
    end    
  end

  it "should return the same structure dump as original oracle adapter" do
    @new_conn.structure_dump.should == @old_conn.structure_dump
  end

  it "should return the same structure drop as original oracle adapter" do
    @new_conn.structure_drop.should == @old_conn.structure_drop
  end
  
  it "should return the character size of nvarchar fields" do
    @new_conn.execute <<-SQL
      CREATE TABLE nvarchartable (
        session_id  NVARCHAR2(255) DEFAULT NULL
      )
    SQL
    if /.*session_id nvarchar2\((\d+)\).*/ =~ @new_conn.structure_dump
       "#$1".should == "255"
    end
    @new_conn.execute "DROP TABLE nvarchartable"
  end
end

describe "OracleEnhancedAdapter database stucture dump extentions" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE nvarchartable (
        unq_nvarchar  NVARCHAR2(255) DEFAULT NULL
      )
    SQL
  end
  
  after(:all) do
    @conn.execute "DROP TABLE nvarchartable"
  end
  
  it "should return the character size of nvarchar fields" do
    if /.*unq_nvarchar nvarchar2\((\d+)\).*/ =~ @conn.structure_dump
       "#$1".should == "255"
    end
  end
end

describe "OracleEnhancedAdapter database session store" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE sessions (
        id          NUMBER(38,0) NOT NULL,
        session_id  VARCHAR2(255) DEFAULT NULL,
        data        CLOB DEFAULT NULL,
        created_at  DATE DEFAULT NULL,
        updated_at  DATE DEFAULT NULL,
        PRIMARY KEY (ID)
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE sessions_seq  MINVALUE 1 MAXVALUE 999999999999999999999999999
        INCREMENT BY 1 START WITH 10040 CACHE 20 NOORDER NOCYCLE
    SQL
  end

  after(:all) do
    @conn.execute "DROP TABLE sessions"
    @conn.execute "DROP SEQUENCE sessions_seq"
  end

  it "should create sessions table" do
    ActiveRecord::Base.connection.tables.grep("sessions").should_not be_empty
  end

  it "should save session data" do
    @session = CGI::Session::ActiveRecordStore::Session.new :session_id => "111111", :data  => "something" #, :updated_at => Time.now
    @session.save!
    @session = CGI::Session::ActiveRecordStore::Session.find_by_session_id("111111")
    @session.data.should == "something"
  end

  it "should change session data when partial updates enabled" do
    return pending("Not in this ActiveRecord version") unless CGI::Session::ActiveRecordStore::Session.respond_to?(:partial_updates=)
    CGI::Session::ActiveRecordStore::Session.partial_updates = true
    @session = CGI::Session::ActiveRecordStore::Session.new :session_id => "222222", :data  => "something" #, :updated_at => Time.now
    @session.save!
    @session = CGI::Session::ActiveRecordStore::Session.find_by_session_id("222222")
    @session.data = "other thing"
    @session.save!
    # second save should call again blob writing callback
    @session.save!
    @session = CGI::Session::ActiveRecordStore::Session.find_by_session_id("222222")
    @session.data.should == "other thing"
  end

  it "should have one enhanced_write_lobs callback" do
    return pending("Not in this ActiveRecord version") unless CGI::Session::ActiveRecordStore::Session.respond_to?(:after_save_callback_chain)
    CGI::Session::ActiveRecordStore::Session.after_save_callback_chain.select{|cb| cb.method == :enhanced_write_lobs}.should have(1).record
  end

  it "should not set sessions table session_id column type as integer if emulate_integers_by_column_name is true" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.emulate_integers_by_column_name = true
    columns = @conn.columns('sessions')
    column = columns.detect{|c| c.name == "session_id"}
    column.type.should == :string
  end

end

describe "OracleEnhancedAdapter ignore specified table columns" do
  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
    @conn.execute <<-SQL
      CREATE TABLE test_employees (
        id            NUMBER,
        first_name    VARCHAR2(20),
        last_name     VARCHAR2(25),
        email         VARCHAR2(25),
        phone_number  VARCHAR2(20),
        hire_date     DATE,
        job_id        NUMBER,
        salary        NUMBER,
        commission_pct  NUMBER(2,2),
        manager_id    NUMBER(6),
        department_id NUMBER(4,0),
        created_at    DATE
      )
    SQL
    @conn.execute <<-SQL
      CREATE SEQUENCE test_employees_seq  MINVALUE 1
        INCREMENT BY 1 START WITH 1 CACHE 20 NOORDER NOCYCLE
    SQL
  end
  
  after(:all) do
    @conn.execute "DROP TABLE test_employees"
    @conn.execute "DROP SEQUENCE test_employees_seq"
  end

  after(:each) do
    Object.send(:remove_const, "TestEmployee")
  end

  it "should ignore specified table columns" do
    class TestEmployee < ActiveRecord::Base
      ignore_table_columns  :phone_number, :hire_date
    end
    TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }.should be_empty
  end

  it "should ignore specified table columns specified in several lines" do
    class TestEmployee < ActiveRecord::Base
      ignore_table_columns  :phone_number
      ignore_table_columns  :hire_date
    end
    TestEmployee.connection.columns('test_employees').select{|c| ['phone_number','hire_date'].include?(c.name) }.should be_empty
  end

  it "should not ignore unspecified table columns" do
    class TestEmployee < ActiveRecord::Base
      ignore_table_columns  :phone_number, :hire_date
    end
    TestEmployee.connection.columns('test_employees').select{|c| c.name == 'email' }.should_not be_empty
  end


end

describe "OracleEnhancedAdapter table and sequence creation with non-default primary key" do

  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :keyboards, :force => true, :id  => false do |t|
          t.primary_key :key_number
          t.string      :name
        end
        create_table :id_keyboards, :force => true do |t|
          t.string      :name
        end
      end
    end
    class Keyboard < ActiveRecord::Base
      set_primary_key :key_number
    end
    class IdKeyboard < ActiveRecord::Base
    end
  end
  
  after(:all) do
    ActiveRecord::Schema.define do
      suppress_messages do
        drop_table :keyboards
        drop_table :id_keyboards
      end
    end
    Object.send(:remove_const, "Keyboard")
    Object.send(:remove_const, "IdKeyboard")
  end
  
  it "should create sequence for non-default primary key" do
    ActiveRecord::Base.connection.next_sequence_value(Keyboard.sequence_name).should_not be_nil
  end

  it "should create sequence for default primary key" do
    ActiveRecord::Base.connection.next_sequence_value(IdKeyboard.sequence_name).should_not be_nil
  end
end

describe "OracleEnhancedAdapter without composite_primary_keys" do

  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    Object.send(:remove_const, 'CompositePrimaryKeys') if defined?(CompositePrimaryKeys)
    class Employee < ActiveRecord::Base
      set_primary_key :employee_id
    end
  end

  it "should tell ActiveRecord that count distinct is supported" do
    ActiveRecord::Base.connection.supports_count_distinct?.should be_true
  end

  it "should execute correct SQL COUNT DISTINCT statement" do
    lambda { Employee.count(:employee_id, :distinct => true) }.should_not raise_error
  end

end

describe "OracleEnhancedAdapter sequence creation parameters" do

  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
  end

  def create_test_employees_table(sequence_start_value = nil)
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :test_employees, sequence_start_value ? {:sequence_start_value => sequence_start_value} : {} do |t|
          t.string      :first_name
          t.string      :last_name
        end
      end
    end
  end
  
  def save_default_sequence_start_value
    @saved_sequence_start_value = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value
  end

  def restore_default_sequence_start_value
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = @saved_sequence_start_value
  end

  before(:each) do
    save_default_sequence_start_value
  end
  after(:each) do
    restore_default_sequence_start_value
    ActiveRecord::Schema.define do
      suppress_messages do
        drop_table :test_employees
      end
    end
    Object.send(:remove_const, "TestEmployee")
  end

  it "should use default sequence start value 10000" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value.should == 10000

    create_test_employees_table
    class TestEmployee < ActiveRecord::Base; end

    employee = TestEmployee.create!
    employee.id.should == 10000
  end

  it "should use specified default sequence start value" do
    ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = 1

    create_test_employees_table
    class TestEmployee < ActiveRecord::Base; end

    employee = TestEmployee.create!
    employee.id.should == 1
  end

  it "should use sequence start value from table definition" do
    create_test_employees_table(10)
    class TestEmployee < ActiveRecord::Base; end

    employee = TestEmployee.create!
    employee.id.should == 10
  end

  it "should use sequence start value and other options from table definition" do
    create_test_employees_table("100 NOCACHE INCREMENT BY 10")
    class TestEmployee < ActiveRecord::Base; end

    employee = TestEmployee.create!
    employee.id.should == 100
    employee = TestEmployee.create!
    employee.id.should == 110
  end

end

describe "OracleEnhancedAdapter table and column comments" do

  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "hr",
                                            :password => "hr")
    @conn = ActiveRecord::Base.connection
  end

  def create_test_employees_table(table_comment=nil, column_comments={})
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :test_employees, :comment => table_comment do |t|
          t.string      :first_name, :comment => column_comments[:first_name]
          t.string      :last_name, :comment => column_comments[:last_name]
        end
      end
    end
  end

  after(:each) do
    ActiveRecord::Schema.define do
      suppress_messages do
        drop_table :test_employees
      end
    end
    Object.send(:remove_const, "TestEmployee")
    ActiveRecord::Base.table_name_prefix = nil
  end

  it "should create table with table comment" do
    table_comment = "Test Employees"
    create_test_employees_table(table_comment)
    class TestEmployee < ActiveRecord::Base; end
    
    @conn.table_comment("test_employees").should == table_comment
    TestEmployee.table_comment.should == table_comment
  end

  it "should create table with columns comment" do
    column_comments = {:first_name => "Given Name", :last_name => "Surname"}
    create_test_employees_table(nil, column_comments)
    class TestEmployee < ActiveRecord::Base; end
    
    [:first_name, :last_name].each do |attr|
      @conn.column_comment("test_employees", attr.to_s).should == column_comments[attr]
    end
    [:first_name, :last_name].each do |attr|
      TestEmployee.columns_hash[attr.to_s].comment.should == column_comments[attr]
    end
  end

  it "should create table with table and columns comment and custom table name prefix" do
    ActiveRecord::Base.table_name_prefix = "xxx_"
    table_comment = "Test Employees"
    column_comments = {:first_name => "Given Name", :last_name => "Surname"}
    create_test_employees_table(table_comment, column_comments)
    class TestEmployee < ActiveRecord::Base; end
    
    @conn.table_comment(TestEmployee.table_name).should == table_comment
    TestEmployee.table_comment.should == table_comment
    [:first_name, :last_name].each do |attr|
      @conn.column_comment(TestEmployee.table_name, attr.to_s).should == column_comments[attr]
    end
    [:first_name, :last_name].each do |attr|
      TestEmployee.columns_hash[attr.to_s].comment.should == column_comments[attr]
    end
  end

end

describe "OracleEnhancedAdapter with schema specified" do

  before(:all) do
    ActiveRecord::Base.establish_connection(:adapter => "oracle_enhanced",
                                            :database => "xe",
                                            :username => "emp",
                                            :password => "emp",
                                            :schema => "hr")
    class Employee < ActiveRecord::Base
      set_primary_key :employee_id
    end
  end

  it "should find tables owned by other schema" do
    lambda { Employee.first }.should_not raise_error
  end

end
