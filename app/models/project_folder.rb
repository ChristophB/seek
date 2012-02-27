class ProjectFolder < ActiveRecord::Base
  belongs_to :project
  belongs_to :parent,:class_name=>"ProjectFolder",:foreign_key=>:parent_id
  has_many :children,:class_name=>"ProjectFolder",:foreign_key=>:parent_id, :order=>:title, :after_add=>:update_child
  has_many :project_folder_assets, :dependent=>:destroy

  before_destroy :deletable?
  before_destroy :unsort_assets_and_remove_children


  named_scope :root_folders, lambda { |project| {
    :conditions=>{:project_id=>project.id,:parent_id=>nil},:order=>"LOWER(title)"
    }
  }

  validates_presence_of :project,:title

  def update_child child
    child.project = project
    child.parent = self
  end

  def assets
    project_folder_assets.collect{|pfa| pfa.asset}
  end

  #assets that are authorized to be shown for the current user
  def authorized_assets
    assets.select{|a| a.can_view?}
  end

  #what is displayed in the tree
  def label
    "#{title} (#{assets.count})"
  end

  def self.new_items_folder project
    ProjectFolder.find(:first,:conditions=>{:project_id=>project.id,:incoming=>true})
  end

  #constucts the default project folders for a given project from a yaml file, by default using $RAILS_ROOT/config/default_data/default_project_folders.yml
  def self.initialize_default_folders project, yaml_path=File.join(Rails.root,"config","default_data","default_project_folders.yml")
    raise Exception.new("This project already has folders defined") unless ProjectFolder.root_folders(project).empty?

    yaml=YAML::load_file yaml_path
    folders={}

    #create individual folder items
    yaml.keys.each do |key|
      desc = yaml[key]
      new_folder=ProjectFolder.create :title=>desc["title"],
                                      :editable=>(desc["editable"].nil? ? true : desc["editable"]),
                                      :incoming=>(desc["incoming"].nil? ? false : desc["incoming"]),
                                      :deletable=>(desc["deletable"].nil? ? true : desc["deletable"]),
                                      :project=>project
      folders[key]=new_folder
    end

    #now assign children
    yaml.keys.each do |key|
      desc=yaml[key]
      if desc.has_key?("children")
        parent = folders[key]
        desc["children"].split(",").each do |child|
          folder = folders[child.strip]
          unless folder.nil?
            parent.children << folder
          else
            Rails.logger.error("Default project folder for key #{child} not found")
          end
        end
        parent.save!
      end
    end

    ProjectFolder.root_folders project
  end

  #adds a child with the given title, and makes sure the project is set correctly
  def add_child title
    child = ProjectFolder.new(:title=>title)
    children << child
    child
  end

  def add_assets assets
    assets = Array(assets)
    assets.each do |asset|
      pfa = ProjectFolderAsset.new :asset=>asset,:project_folder=>self
      pfa.save!
    end
  end

  #moves assets to this folder, from the source folder (source folder needed incase the asset belongs to more than 1 folder)
  def move_assets assets,source_folder
    assets=Array(assets)
    if (project_id == source_folder.project_id)
      assets.each do |asset|
        link = ProjectFolderAsset.find(:first,:conditions=>{:asset_id=>asset.id,:asset_type=>asset.class.name,:project_folder_id=>source_folder.id})
        link.project_folder=self
        link.save!
      end
    end
  end

  #temporary method to destroy folders for a project, useful whilst developing
  def self.nuke project
    folders = ProjectFolder.find(:all,:conditions=>{:project_id=>project.id})
    folder_assets = ProjectFolderAsset.all.select{|pfa| pfa.project_folder.nil? || pfa.project_folder.try(:project_id)==project.id}
    folder_assets.each {|a| a.destroy}
    folders.each {|f| f.deletable=true ; f.destroy}

  end

  def unsort_assets_and_remove_children

    new_items_folder=ProjectFolder.new_items_folder(project)
    if (new_items_folder && !self.incoming?)
      disable_authorization_checks do
        new_items_folder.add_assets(assets)
      end
    end
    children.destroy_all
  end

end
