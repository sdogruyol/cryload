# cryload

HTTP benchmarking tool writen in [Crystal](http://crystal-lang.org/)

## Installation

```
git clone https://github.com/Sdogruyol/cryload.git && cd cryload
crystal build src/cryload.cr --release
```

## Usage
You can specify the number of requests after the url. The default request number is 1000.

```
./cryload http://wwww.example.com 10000
```

## Development

DONE:

1. Request number
2. Pretty output
3. Performance
4. Kill signal handling

TODO:

1. Duration
2. Multithreading

## Contributing

1. Fork it ( https://github.com/[your-github-name]/cryload/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [Sdogruyol](https://github.com/[sdogruyol]) Sdogruyol - creator, maintainer
