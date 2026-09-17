module Admin
  class BackupController < AdminController
    # Produces a portable SQL dump of the live database using the connection's
    # own schema and rows, so the export always matches what the app is
    # actually reading rather than a hand-maintained list of tables.
    def export
      unless can?("backup.export")
        return redirect_to(admin_root_path, alert: "You do not have the backup.export permission.")
      end

      audit!("backup.export", target: "database", detail: "downloaded SQL dump")

      send_data dump_sql,
                filename: "twitter-backup.sql",
                type: "application/sql",
                disposition: "attachment"
    end

    private

    def dump_sql
      connection = ActiveRecord::Base.connection
      lines = []

      table_names(connection).each do |table|
        lines << "#{table_ddl(connection, table)};"

        columns = column_names(connection, table)
        connection.select_all("SELECT * FROM #{connection.quote_table_name(table)}").each do |row|
          values = columns.map { |column| literal(row[column]) }
          lines << "INSERT INTO #{table} (#{columns.join(',')}) VALUES (#{values.join(',')});"
        end

        lines << ""
      end

      lines.join("\n")
    end

    # Application tables only; SQLite's internal bookkeeping tables are skipped.
    def table_names(connection)
      connection.tables.sort.reject { |name| name.start_with?("sqlite_") }
    end

    def table_ddl(connection, table)
      row = connection.select_one(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name = #{connection.quote(table)}"
      )
      row&.fetch("sql", nil) || "CREATE TABLE #{table} ()"
    end

    def column_names(connection, table)
      connection.columns(table).map(&:name)
    end

    def literal(value)
      case value
      when nil     then "NULL"
      when Numeric then value.to_s
      else "'#{value.to_s.gsub("'", "''")}'"
      end
    end
  end
end