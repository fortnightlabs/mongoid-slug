# require 'moped/bson/object_id'

module Mongoid
  module Slug
    class Criteria < Mongoid::Criteria
      # Find the matchind document(s) in the criteria for the provided ids or slugs.
      #
      # If the document _ids are of the type Moped::BSON::ObjectId, and all the supplied parameters are
      # convertible to Moped::BSON::ObjectId (via Moped::BSON::ObjectId#from_string), finding will be
      # performed via _ids.
      #
      # If the document has any other type of _id field, and all the supplied parameters are of the same
      # type, finding will be performed via _ids.
      #
      # Otherwise finding will be performed via slugs.
      #
      # @example Find by an id.
      #   criteria.find(Moped::BSON::ObjectId.new)
      #
      # @example Find by multiple ids.
      #   criteria.find([ Moped::BSON::ObjectId.new, Moped::BSON::ObjectId.new ])
      #
      # @example Find by a slug.
      #   criteria.find('some-slug')
      #
      # @example Find by multiple slugs.
      #   criteria.find([ 'some-slug', 'some-other-slug' ])
      #
      # @param [ Array<Object> ] args The ids or slugs to search for.
      #
      # @return [ Array<Document>, Document ] The matching document(s).
      def find(*args)
        look_like_slugs?(args.__find_args__) ? find_by_slug!(*args) : super
      end

      # Find the matchind document(s) in the criteria for the provided slugs.
      #
      # @example Find by a slug.
      #   criteria.find('some-slug')
      #
      # @example Find by multiple slugs.
      #   criteria.find([ 'some-slug', 'some-other-slug' ])
      #
      # @param [ Array<Object> ] args The slugs to search for.
      #
      # @return [ Array<Document>, Document ] The matching document(s).
      def find_by_slug!(*args)
        slugs = args.__find_args__
        raise_invalid if slugs.any?(&:nil?)
        for_slugs(slugs).execute_or_raise_for_slugs(slugs, args.multi_arged?)
      end

      def look_like_slugs?(args)
        return false unless args.all? { |id| id.is_a?(String) }
        id_field = @klass.fields['_id']
        @slug_strategy ||= id_field.options[:slug_id_strategy] || build_slug_strategy(id_field.type)
        args.none? { |id| @slug_strategy.call(id) }
      end

      protected

      # unless a :slug_id_strategy option is defined on the id field,
      # use object_id or string strategy depending on the id_type
      # otherwise default for all other id_types
      def build_slug_strategy id_type
        type_method = id_type.to_s.downcase.split('::').last + "_slug_strategy"
        self.respond_to?(type_method) ? method(type_method) : lambda {|id| false}
      end

      # a string will not look like a slug if it looks like a legal ObjectId
      def objectid_slug_strategy id
        Moped::BSON::ObjectId.legal?(id)
      end

      # a string will always look like a slug
      def string_slug_strategy id
        true
      end


      def for_slugs(slugs)
        where({ _slugs: { '$in' => slugs } }).limit(slugs.length)
      end

      def execute_or_raise_for_slugs(slugs, multi)
        result = uniq
        check_for_missing_documents_for_slugs!(result, slugs)
        multi ? result : result.first
      end

      def check_for_missing_documents_for_slugs!(result, slugs)
        missing_slugs = slugs - result.map(&:slugs).flatten

        if !missing_slugs.blank? && Mongoid.raise_not_found_error
          raise Errors::DocumentNotFound.new(klass, slugs, missing_slugs)
        end
      end
    end
  end
end
