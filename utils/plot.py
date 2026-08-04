import sys
import numpy as np
import xarray as xr
from datetime import datetime, timedelta

import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER
import matplotlib.ticker as mticker
import matplotlib.colors as colors  
from matplotlib.colors import BoundaryNorm

begTime = datetime(2024, 1, 2, 13)

#lon = list(np.arange(0, 180) + 0.5) + list(np.arange(-180, 0) + 0.5)
lon = np.arange(-180, 180) + 0.5
lat = np.arange(-90, 90) + 0.5

clevs = [0.001, 0.01, 0.05, 0.1, 0.5, 1, 5, 10, 15, 20, 30, 50]

for i in range(72):
    data = xr.open_dataset(begTime.strftime('../naqp_d01_%Y%m%d%H.nc'))
    conc = data.PM25.values[0, :, :]
    fig = plt.figure(figsize=(10,5),dpi=300)
    ax = fig.subplots(1,1,subplot_kw={'projection':ccrs.PlateCarree()})
    extent = [-180, 180, -90, 90] 
    ax.add_feature(cfeature.COASTLINE.with_scale("50m"),lw=0.8)
    gl = ax.gridlines(draw_labels=True,linewidth=0.2,color='k',linestyle="--",alpha=0.5)
    gl.xlabels_top = False
    gl.ylabels_right=False
    gl.xformatter = LONGITUDE_FORMATTER
    gl.yformatter = LATITUDE_FORMATTER
    gl.xlocator   = mticker.FixedLocator(np.arange(extent[0],extent[1],30))
    gl.ylocator   = mticker.FixedLocator(np.arange(extent[2],extent[3],30))
    gl.xlabel_style = {"size":12}
    gl.ylabel_style = {"size":12}

    cmaps = plt.get_cmap('rainbow')
    norm = BoundaryNorm(clevs, cmaps.N)
    conc = np.concatenate((conc[:, 180:], conc[:, :180]), axis=1)
    pres_shading = ax.contourf(lon, lat, conc, levels=clevs,cmap="rainbow",extend="both",norm=norm)#
    #pres_shading = ax.contourf(lon[:180], lat, conc[:, 180:], levels=clevs,cmap="rainbow",extend="both",norm=norm)#
    #pres_shading = ax.contourf(lon[180:], lat, conc[:, :180], levels=clevs,cmap="rainbow",extend="both",norm=norm)#

    pad = 0.02
    width= 0.02
    pos=ax.get_position()
    cax1 = fig.add_axes([pos.xmax+pad,pos.ymin,width,pos.ymax-pos.ymin])
    cbar = plt.colorbar(pres_shading, orientation="vertical",cax=cax1)
    cbar.ax.tick_params(labelsize=10)

    ax.set_title('pm25 ' + begTime.strftime('%Y%m%d%H'), loc="center",fontsize=20)

    plt.savefig(begTime.strftime('%Y%m%d%H') + '.png')

    begTime += timedelta(hours=1)

