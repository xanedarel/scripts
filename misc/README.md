# Miscellaneous scripts
### nasa-pia.sh
When you download pictures from NASA's website (eg:) they are named PIA[0-9]*.tif .

I had a huge collection of those files, alongside files I renamed with a more classic and meaninful name as displayed on Nasa's website (eg: The View from Iapetus.tif).

Having duplicates in this form I needed a way to compare them, remove any PIA file if it's sha1sum was found to be matching the new naming scheme.

And also edit filenames which sometimes have a trailing [::space::] character, as the formatting from the source website is not regular.
