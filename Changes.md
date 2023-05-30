# Reasons to fork

* Drop links to Amazon
* use own configurable URL for CoverService
* use ISBN-13 or ISBN-10 for cover (configurable)

#  Additional comments
On the first try, i changed the URL for the covers direct in report.tt.
This leads to unknkown images because the used function *"GetNormalizedISBN"* returns ISBN-10 but my provider needs ISBN-13 to find a cover. So the function *GetNormalizedISBN* needs to be replaced by *NormalizeISBN*. This functin can return both (ISBN-13 or ISBN-1), depending on paramters given.


# ToDo
* Drop Logo in config
* Drop unneeded paramters from config (i.e. coce)
* add URL-field for own cover-CoverService
* add config für isbn-format (ISBN13 or ISBN10)





# changelog
* renamed CoverFlow.pm to MMOsCoverFlow.pw
* moved all from ByWater.com to mmo74.de (in all files and directorys)
* link to *NoImage.png* moved to /api/v1/..


