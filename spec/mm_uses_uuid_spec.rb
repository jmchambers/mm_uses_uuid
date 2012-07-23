require File.expand_path('../../lib/mm_uses_uuid', __FILE__)
require 'ruby-debug'

describe MmUsesUuid do
  
  before(:all) do    
    class Group
      include MongoMapper::Document
      plugin  MmUsesUuid
      
      key  :name, String
      belongs_to :owner, :class_name => 'UuidModel', :required => true
      has_many :people, :class_name => 'Person'
      
      uuid_lsn 0
      
    end
    
    class Person
      include MongoMapper::Document
      plugin  MmUsesUuid
      
      key :name
      key :age
      
      key  :interest_ids, Set
      has_many :interests, :in => :interest_ids, :class_name => 'UuidModel' # this allows many-to-many polymorphic interests without the need for groups and people to be stored in a single collection
      
      belongs_to :group
      
      uuid_lsn 0xf
      
    end
    
    MongoMapper.connection = Mongo::Connection.new('localhost', 27017)
    MongoMapper.database = 'mm_uses_uuid_test'
    
  end
  
  before(:each) do
    #we have to use a before(:each) to get the stubbing to work :(
    SecureRandom.stub!(:uuid).and_return(
      "22222222-2222-4222-y222-222222222222",
      "11111111-1111-4111-y111-111111111111",
      "11111111-1111-4111-y111-111111111111", #we repeat these so that our safe uuid creation tests will detect a collision and be forced to search
      "11111111-1111-4111-y111-111111111111",
      "11111111-1111-4111-y111-111111111111",
      "33333333-3333-4333-y333-333333333333"
    )
    
    @person = Person.new(name: 'Jon', age: 33)
    @person.save
    
    @group = Group.new(name: 'mongo_mapper fanclub')
    @group.owner = @person
    @group.save
    
    @person.interests << @group
    @person.interests << @person #I'm very self-centred
    @person.save
    
  end
  
  it "should cause newly initialized objects to have a BSON::Binary uuid" do
    @group._id.should be_an_instance_of(BSON::Binary)
    @group._id.subtype.should == BSON::Binary::SUBTYPE_UUID
  end
  
  it "should replace the least significant bits with the integer specified using uuid_lsn" do
    @group._id.to_s.slice(-1).should == '0'
    @person._id.to_s.slice(-1).should == 'f'
  end

  it "should perform a find on the right collection if MongoMapper.find is used" do
    UuidModel.find(@person.id, @group.id).map(&:name).should include(@person.name, @group.name)
  end
  
  it "should support polymorphic many to many associations that use LSN encoding" do
    person = Person.find_by_name 'Jon'
    person.interests.map(&:name).should include(@person.name, @group.name)
  end
  
  it "should return an array for many to many associations when there is only one associated item" do
    person = Person.new
    person.interests << @group
    person.interests.should be_an_instance_of(Array)
  end

  it "should not set a new uuid if one as passed as a param" do
    group_with_passed_id = Group.new(:id => BSON::Binary.new("3333333333334333y333333333333330", BSON::Binary::SUBTYPE_UUID))
    group_with_passed_id.id.to_s.should == "3333333333334333y333333333333330"
    
    group_with_passed_id = Group.new('_id' => BSON::Binary.new("3333333333334333y333333333333330", BSON::Binary::SUBTYPE_UUID))
    group_with_passed_id.id.to_s.should == "3333333333334333y333333333333330"
  end
  
  it "should have a useful inspect method that shows the uuid string" do
    @group._id.inspect.should == "<BSON::Binary:'#{@group._id.to_s}'>"
  end
  
  it "should report that uuid BSON::Binary objects are eql? if they encode the same string" do
    a = BSON::Binary.new("3333333333334333y333333333333330", BSON::Binary::SUBTYPE_UUID)
    b = BSON::Binary.new("3333333333334333y333333333333330", BSON::Binary::SUBTYPE_UUID)
    a.should eql b
  end

  it "should cause associated objects to reference the parent uuid" do
    @group.people << @person
    @person.group_id.should == @group._id
  end
  
  it "should ensure that the uuid is unique if :ensure_unique_in is set" do
    safe_new_group = Group.new
    safe_new_group.find_new_uuid(:ensure_unique_in => Group)
    safe_new_group._id.to_s.should == "3333333333334333y333333333333330"
  end
  
  context 'finding by uuid' do
    
    it "should find with a BSON::Binary uuid" do
      found_group = UuidModel.find(@group._id)
      found_group._id.should == @group._id
    end
    
    it "should find with a String uuid" do
      found_group = UuidModel.find(@group._id.to_s)
      found_group._id.should == @group._id
    end
    
    it "find! should raise an error if an id is not found" do
      lambda { UuidModel.find! "ffffffffffff4fffyffffffffffffff0" }.should raise_error(MongoMapper::DocumentNotFound)
    end
    
    it "find! should raise an error if one of many ids is not found" do
      lambda { UuidModel.find! "ffffffffffff4fffyffffffffffffff0", @group._id }.should raise_error(MongoMapper::DocumentNotFound)
    end
    
  end
  
  context "finding indirectly via belongs_to assoc" do
    
    it "should find associated objects" do
      @group.owner.should == @person
    end
    
  end
  
  after(:each) do
    Group.delete_all; Person.delete_all
  end
  
end