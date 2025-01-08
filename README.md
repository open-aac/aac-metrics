# AAC Metrics

A tool for analysing and comparing grid-based AAC board sets

To compare two datasets 
`ruby setup.rb qc24 qc112`

To compare two datasets and export the minimal obfset for the first
`ruby setup.rb qc24 qc112 export`
`ruby setup.rb qc24 qc112 render` # updates interactive preview in sets/preview.html

To generate an obfset from an external data source
`ruby lib/ingester.rb path/to/manifest-from-unzipped-obz.json`
`ruby lib/ingester.rb path/to/compiled-set.obfset`
`ruby lib/ingester.rb path/to/root-file.obf`


NOTE: if you add an obfset to sets, it will be accessible
simply by its prefix. If you add ".common" to the filename
similar to the existing files, it will be added to the 
corpus of "common" word sets.

## License

Licensed under the MIT License.