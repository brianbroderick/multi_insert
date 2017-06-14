# multi_insert
Bulk Insert for ActiveRecord & PostgreSQL

This allows you to bulk insert using ActiveRecord, which will greatly increase the speed of ActiveRecord inserts.
It accepts an array of hashes as its first param, where the hash keys are column names. 
You can batch insert and it also supports upserts if you add an ON CONFLICT clause.

# Examples:

This example assumes a model called Page with 2 columns, "title" and "status". 
Upserts in PG require a unique index. In this example, it's on the "title" column as seen in the DO UPDATE clause. 
The shard key in the options hash is optional. If it's present, it expects that the Octopus gem is installed.
The returning key is also optional and only needed if you want to cascade inserts.

```
array_of_hashes = [{ title: "Foo", status: "pending" },
                   { title: "Bar", status: "active" },
                   { title: "Baz", status: "deleted" }]


::MultiInsert.call(
      array_of_hashes,
      { shard: shard,
        model: ::Page,
        returning: "id",
        ignore_attributes: ["id"],
        sql_append: "ON CONFLICT(unique_hash) DO UPDATE SET title = EXCLUDED.title" }
    )
```


# Dependencies

* ActiveRecord 4 or 5
* Octopus, if you want sharding support. 

# TODO

* Turn into a Gem
