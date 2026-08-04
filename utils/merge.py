import sys
import glob

import numpy as np
import xarray as xr

varname = sys.argv[1]

fileNames = sorted(glob.glob('naqp_d0?_*.nc'))
maxDom = int(fileNames[-1][7:8])
for i in range(maxDom):
    data = []
    for thisFile in fileNames:
        if 'd0{dom}'.format(dom=i+1) in thisFile:
            xdata = xr.open_dataset(thisFile)
            try:
               data.append(xdata[varname].values)
            except:
               pass
    data = xr.DataArray(np.array(data), dims=("time", "layer", "south_north", "west_east") )
    oFile = 'naqp_d0{dom}.nc'.format(dom=i+1)
    xr.Dataset({varname:data}).to_netcdf(oFile, format='NETCDF4')
