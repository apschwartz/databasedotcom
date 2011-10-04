require 'rspec'
require 'spec_helper'
require 'databasedotcom'

describe Databasedotcom::Sobject::Sobject do
  class TestClass < Databasedotcom::Sobject::Sobject
  end

  before do
    @client = Databasedotcom::Client.new(File.join(File.dirname(__FILE__), "../../fixtures/databasedotcom.yml"))
    @client.authenticate(:token => "foo", :instance_url => "https://na9.salesforce.com")
    TestClass.client = @client
  end

  describe "materialization" do
    context "with a valid Sobject name" do
      response = JSON.parse(File.read(File.join(File.dirname(__FILE__), "../../fixtures/sobject/sobject_describe_success_response.json")))

      it "requests a description of the class" do
        @client.should_receive(:describe_sobject).with("TestClass").and_return(response)
        TestClass.materialize("TestClass")
      end

      context "with a response" do
        before do
          @client.stub(:describe_sobject).and_return(response)
          TestClass.materialize("TestClass")
          @sobject = TestClass.new
        end

        describe ".attributes" do
          it "returns the attributes for this Sobject" do
            TestClass.attributes.should_not be_nil
            TestClass.attributes.should =~ response["fields"].collect { |f| f["name"] }
          end
        end

        describe ".relatedLists" do
          it "returns the relatedLists for this Sobject" do
            TestClass.relatedLists.should_not be_nil
            TestClass.relatedLists.should =~ response["childRelationships"].collect { |cr| cr["relationshipName"]}.find_all {|rn| rn}
          end
        end

        describe "getters and setters" do
          response["fields"].collect { |f| f["name"] }.each do |name|
            it "creates a getter and setter for the #{name} attribute" do
              @sobject.should respond_to(name.to_sym)
              @sobject.should respond_to("#{name}=".to_sym)
            end
          end
          response["childRelationships"].collect { |cr| cr["relationshipName"]}.find_all {|rn| rn}.each do |name|
            it "creates a getter and setter for the #{name} attribute" do
              @sobject.should respond_to(name.to_sym)
              @sobject.should respond_to("#{name}=".to_sym)
            end
          end
        end

        describe "default values" do
          response["fields"].each do |f|
            it "sets #{f['name']} to #{f['defaultValueFormula'] ? f['defaultValueFormula'] : 'nil'}" do
              @sobject.send(f["name"].to_sym).should == f["defaultValueFormula"]
            end
          end
        end
      end
    end

    context "with an invalid Sobject name" do
      it "propagates exceptions" do
        @client.should_receive(:describe_sobject).with("TestClass").and_raise(Databasedotcom::SalesForceError.new(double("result", :body => "{}")))
        lambda {
          TestClass.materialize("TestClass")
        }.should raise_error(Databasedotcom::SalesForceError)
      end
    end
  end

  context "with a materialized class" do
    before do
      response = JSON.parse(File.read(File.join(File.dirname(__FILE__), "../../fixtures/sobject/sobject_describe_success_response.json")))
      @client.should_receive(:describe_sobject).with("TestClass").and_return(response)
      TestClass.materialize("TestClass")
      @field_names = TestClass.description["fields"].collect { |f| f["name"] }
    end

    describe ".new" do
      it "creates a new in-memory instance with the specified attributes" do
        obj = TestClass.new("Name" => "foo")
        obj.Name.should == "foo"
        obj.should be_new_record
      end
    end

    describe ".create" do
      it "returns a new instance with the specified attributes" do
        @client.should_receive(:create).with(TestClass, "moo").and_return("gar")
        TestClass.create("moo").should == "gar"
      end
    end

    describe ".find" do
      context "with a valid id" do
        it "returns the found instance" do
          @client.should_receive(:find).with(TestClass, "abc").and_return("bar")
          TestClass.find("abc").should == "bar"
        end
      end

      context "with an invalid id" do
        it "propagates exceptions" do
          @client.should_receive(:find).with(TestClass, "abc").and_raise(Databasedotcom::SalesForceError.new(double("result", :body => "{}")))
          lambda {
            TestClass.find("abc")
          }.should raise_error(Databasedotcom::SalesForceError)
        end
      end
    end

    describe ".all" do
      it "returns a paginated enumerable containing all instances" do
        @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass").and_return("foo")
        TestClass.all.should == "foo"
      end
    end

    describe ".query" do
      it "constructs and submits a SOQL query" do
        @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'foo'").and_return("bar")
        TestClass.query("Name = 'foo'").should == "bar"
      end
    end

    describe ".delete" do
      it "deletes a record specified by id" do
        @client.should_receive(:delete).with("TestClass", "recordId").and_return("deleteResponse")
        TestClass.delete("recordId").should == "deleteResponse"
      end
    end

    describe ".first" do
      it "loads the first record" do
        @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass ORDER BY Id ASC LIMIT 1").and_return(["foo"])
        TestClass.first.should == "foo"
      end

      it "optionally includes SOQL conditions" do
        @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE conditions ORDER BY Id ASC LIMIT 1").and_return(["foo"])
        TestClass.first("conditions").should == "foo"
      end
    end

    describe ".last" do
      it "loads the last record" do
        @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass ORDER BY Id DESC LIMIT 1").and_return(["bar"])
        TestClass.last.should == "bar"
      end

      it "optionally includes SOQL conditions" do
        @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE conditions ORDER BY Id DESC LIMIT 1").and_return(["bar"])
        TestClass.last("conditions").should == "bar"
      end
    end

    describe ".coerce_params" do
      it "coerces boolean attributes" do
        TestClass.coerce_params("Checkbox_Field" => "1")["Checkbox_Field"].should be_true
        TestClass.coerce_params("Checkbox_Field" => "0")["Checkbox_Field"].should be_false
        TestClass.coerce_params("Checkbox_Field" => true)["Checkbox_Field"].should be_true
        TestClass.coerce_params("Checkbox_Field" => false)["Checkbox_Field"].should be_false
      end

      it "coerces currency attributes" do
        TestClass.coerce_params("Currency_Field" => "123.4")["Currency_Field"].should == 123.4
        TestClass.coerce_params("Currency_Field" => 123.4)["Currency_Field"].should == 123.4
      end

      it "coerces percent attributes" do
        TestClass.coerce_params("Percent_Field" => "123.4")["Percent_Field"].should == 123.4
        TestClass.coerce_params("Percent_Field" => 123.4)["Percent_Field"].should == 123.4
      end

      it "coerces date fields" do
        today = Date.today
        Date.stub(:today).and_return(today)
        TestClass.coerce_params("Date_Field" => "2010-04-01")["Date_Field"].should == Date.civil(2010, 4, 1)
        TestClass.coerce_params("Date_Field" => "bogus")["Date_Field"].should == Date.today
      end

      it "coerces datetime fields" do
        now = DateTime.now
        DateTime.stub(:now).and_return(now)
        TestClass.coerce_params("DateTime_Field" => "2010-04-01T12:05:10Z")["DateTime_Field"].to_s.should == DateTime.civil(2010, 4, 1, 12, 5, 10).to_s
        TestClass.coerce_params("DateTime_Field" => "bogus")["DateTime_Field"].to_s.should == now.to_s
      end

    end

    describe "dynamic finders" do
      describe "find_by_xxx" do
        context "with a single attribute" do
          it "constructs and executes a query matching the dynamic attributes" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' LIMIT 1").and_return(["bar"])
            TestClass.find_by_Name('Richard').should == "bar"
          end
        end

        context "with multiple attributes" do
          it "constructs and executes a query matching the dynamic attributes" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' AND City = 'San Francisco' LIMIT 1").and_return(["bar"])
            TestClass.find_by_Name_and_City('Richard', 'San Francisco').should == "bar"
          end
        end
      end

      describe "find_all_by_xxx" do
        context "with a single attribute" do
          it "constructs and executes a query matching the dynamic attributes" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard'").and_return("bar")
            TestClass.find_all_by_Name('Richard').should == "bar"
          end
        end

        context "with multiple attributes" do
          it "constructs and executes a query matching the dynamic attributes" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' AND City = 'San Francisco'").and_return("bar")
            TestClass.find_all_by_Name_and_City('Richard', 'San Francisco').should == "bar"
          end
        end
      end
    end

    describe "dynamic creators" do
      describe "find_or_create_by_xxx" do
        context "with a single attribute" do
          it "searches for a record with the specified attribute and creates it if it doesn't exist" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' LIMIT 1").and_return(nil)
            @client.should_receive(:create).with(TestClass, "Name" => "Richard").and_return("gar")
            TestClass.find_or_create_by_Name('Richard').should == "gar"
          end
        end

        context "with multiple attributes" do
          it "searches for a record with the specified attributes and creates it if it doesn't exist" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' AND City = 'San Francisco' LIMIT 1").and_return(nil)
            @client.should_receive(:create).with(TestClass, {"Name" => "Richard", "City" => "San Francisco"}).and_return("bar")
            TestClass.find_or_create_by_Name_and_City('Richard', 'San Francisco').should == "bar"
          end
        end

        context "with a hash argument containing additional attributes" do
          it "finds by the named arguments, but creates by all values in the hash" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' LIMIT 1").and_return(nil)
            @client.should_receive(:create).with(TestClass, "Name" => "Richard", "Email_Field" => "foo@bar.com").and_return("gar")
            TestClass.find_or_create_by_Name("Name" => 'Richard', "Email_Field" => "foo@bar.com").should == "gar"
          end
        end
      end
    end

    describe "dynamic initializers" do
      describe "find_or_initialize_by_xxx" do
        context "with a single attribute" do
          it "searches for a record with the specified attribute and initializes it if it doesn't exist" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' LIMIT 1").and_return(nil)
            TestClass.find_or_initialize_by_Name('Richard').Name.should == "Richard"
          end
        end

        context "with multiple attributes" do
          it "searches for a record with the specified attributes and initializes it if it doesn't exist" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' AND Email_Field = 'fake@email.com' LIMIT 1").and_return(nil)
            result = TestClass.find_or_initialize_by_Name_and_Email_Field('Richard', 'fake@email.com')
            result.Name.should == "Richard"
            result.Email_Field.should == "fake@email.com"
          end
        end

        context "with a hash argument containing additional attributes" do
          it "finds by the named arguments, but initializes by all values in the hash" do
            @client.should_receive(:query).with("SELECT #{@field_names.join(',')} FROM TestClass WHERE Name = 'Richard' LIMIT 1").and_return(nil)
            result = TestClass.find_or_initialize_by_Name("Name" => 'Richard', "Email_Field" => "foo@bar.com")
            result.Name.should == "Richard"
            result.Email_Field.should == "foo@bar.com"
          end
        end
      end
    end

    describe "#attributes=" do
      it "updates the object with the provided attributes" do
        obj = TestClass.new
        obj.Name.should be_nil
        obj.attributes = { "Name" => "foo" }
        obj.Name.should == "foo"
      end
    end

    describe "#save" do
      context "with a new object" do
        before do
          @obj = TestClass.new
          @obj.client = @client
          @obj.Name = "testname"
        end

        it "creates the record remotely with the set attributes" do
          @client.should_receive(:create).and_return("saved")
          @obj.save.should == "saved"
        end

        it "includes only the createable attributes" do
          @client.should_receive(:create) do |clazz, attrs|
            attrs.all? {|attr, value| TestClass.createable?(attr).should be_true}
          end

          @obj.save
        end
      end

      context "with an previously-persisted object" do
        before do
          @obj = TestClass.new
          @obj.client = @client
          @obj.Id = "rid"
        end

        it "updates the record with the attributes of the object" do
          @client.should_receive(:update).and_return("saved updates")
          @obj.save.should == "saved updates"
        end

        it "includes only the updateable attributes" do
          @client.should_receive(:update) do |clazz, id, attrs|
            attrs.all? {|attr, value| TestClass.updateable?(attr).should be_true}
          end

          @obj.save
        end
      end
    end

    describe "#update" do
      it "returns itself with the updated attributes" do
        obj = TestClass.new
        obj.Id = "rid"
        obj.client = @client
        @client.should_receive(:update).with(TestClass, "rid", {"Name" => "newName"}).and_return(true)
        obj.update_attributes({"Name" => "newName"}).Name.should == "newName"
      end
    end

    describe "#delete" do
      it "deletes itself from the database and returns itself" do
        obj = TestClass.new
        obj.Id = "rid"
        obj.client = @client
        @client.should_receive(:delete).with(TestClass, "rid").and_return("destroyResponse")
        obj.delete.should == obj
      end
    end

    describe ".search" do
      it "submits a SOSL query" do
        @client.should_receive(:search).with("foo").and_return("bar")
        TestClass.search("foo").should == "bar"
      end
    end

    describe ".upsert" do
      it "submits an upsert request" do
        @client.should_receive(:upsert).with("TestClass", "externalField", "foo", "Name" => "Richard").and_return("gar")
        TestClass.upsert("externalField", "foo", "Name" => "Richard").should == "gar"
      end
    end

    describe ".label_for" do
      it "returns the label for a named attribute" do
        TestClass.label_for("Picklist_Field").should == "Picklist Label"
      end

      it "raises ArgumentError for unknown attributes" do
        lambda {
          TestClass.label_for("Foobar")
        }.should raise_error(ArgumentError)
      end
    end

    describe ".picklist_values" do
      it "returns an array of picklist values for an attribute" do
        TestClass.picklist_values("Picklist_Field").length.should == 3
      end

      it "raises ArgumentError for unknown attributes" do
        lambda {
          TestClass.picklist_values("Foobar")
        }.should raise_error(ArgumentError)
      end
    end

    describe ".field_type" do
      it "returns the field type for an attribute" do
        TestClass.field_type("Picklist_Field").should == "picklist"
      end

      it "raises ArgumentError for unknown attributes" do
        lambda {
          TestClass.field_type("Foobar")
        }.should raise_error(ArgumentError)
      end
    end

    describe ".updateable?" do
      it "returns the updateable flag for an attribute" do
        TestClass.updateable?("Picklist_Field").should be_true
        TestClass.updateable?("Id").should be_false
      end

      it "raises ArgumentError for unknown attributes" do
        lambda {
          TestClass.updateable?("Foobar")
        }.should raise_error(ArgumentError)
      end
    end

    describe ".createable?" do
      it "returns the createable flag for an attribute" do
        TestClass.createable?("IsDeleted").should be_false
        TestClass.createable?("Picklist_Field").should be_true
      end

      it "raises ArgumentError for unknown attributes" do
        lambda {
          TestClass.createable?("Foobar")
        }.should raise_error(ArgumentError)
      end
    end

    describe "#[]" do
      before do
        @obj = TestClass.new
        @obj.Id = "rid"
        @obj.client = @client
      end

      it "allows enumerable-like access to attributes" do
        @obj.Checkbox_Field = "foo"
        @obj["Checkbox_Field"].should == "foo"
      end

      it "returns nil if the attribute does not exist" do
        @obj["Foobar"].should == nil
      end
    end

    describe "#[]=" do
      before do
        @obj = TestClass.new
        @obj.Id = "rid"
        @obj.client = @client
      end

      it "allows enumerable-like setting of attributes" do
        @obj["Checkbox_Field"] = "foo"
        @obj.Checkbox_Field.should == "foo"
      end

      it "raises Argument error if attribute does not exist" do
        lambda {
          @obj["Foobar"] = "yes"
        }.should raise_error(ArgumentError)
      end
    end

    describe "form_for compatibility methods" do
      describe "#persisted?" do
        it "returns true if the object has an Id" do
          obj = TestClass.new
          obj.should_not be_persisted
          obj.Id = "foo"
          obj.should be_persisted
        end
      end

      describe "#new_record?" do
        it "returns true unless the object has an Id" do
          obj = TestClass.new
          obj.should be_new_record
          obj.Id = "foo"
          obj.should_not be_new_record
        end
      end

      describe "#to_key" do
        it "returns a unique object key" do
          TestClass.new.to_key.should_not == TestClass.new.to_key
        end
      end

      describe "#to_param" do
        it "returns the object Id" do
          obj = TestClass.new
          obj.Id = "foo"
          obj.to_param.should == "foo"
        end
      end
    end

    describe "#reload" do
      it "reloads the object" do
        Databasedotcom::Sobject::Sobject.should_receive(:find).with("foo")
        obj = TestClass.new
        obj.Id = "foo"
        obj.reload
      end
    end
  end
end
