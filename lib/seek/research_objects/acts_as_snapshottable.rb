module Seek #:nodoc:
  module ResearchObjects
    module Snapshottable #:nodoc:

      def self.included(mod)
        mod.extend(ClassMethods)
      end

      module ClassMethods

        def acts_as_snapshottable

          has_many :snapshots, as: :resource, foreign_key: :resource_id

          class_eval do
            extend Seek::ResearchObjects::Snapshottable::SingletonMethods
          end

          include Seek::ResearchObjects::Snapshottable::InstanceMethods

        end

        def is_snapshottable?
          include?(Seek::ResearchObjects::Snapshottable::InstanceMethods)
        end

      end

      module SingletonMethods
      end

      module InstanceMethods

        def snapshot
          ro_file = Seek::ResearchObjects::Generator.instance.generate(self) # This only works for investigations
          blob = ContentBlob.new({
                                     tmp_io_object: ro_file,
                                     content_type: Mime::Type.lookup_by_extension("ro").to_s,
                                     original_filename: self.research_object_filename
                                 })
          snapshot = snapshots.create
          blob.asset = snapshot
          blob.save
        end

      end

    end
  end
end

ActiveRecord::Base.class_eval do
  include Seek::ResearchObjects::Snapshottable
end
