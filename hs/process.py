#!/usr/bin/python3
import sys
import os
from osgeo import gdal
from PIL import Image as PImage, ImageFilter, ImageOps

infile = sys.argv[1]
outfile = sys.argv[2]
tmpFile1 = outfile + "1.tif"
tmpFile2 = outfile + "2.tif"

ds = gdal.Open(infile, gdal.GA_ReadOnly)
ds = gdal.Warp(tmpFile1, ds,
               dstSRS = "EPSG:4326",
               resampleAlg = "cubic",
            #    outputBoundsSRS = "EPSG:3857",
               options = ["TILED=YES"]
               )
ds = gdal.DEMProcessing(tmpFile2, ds, "hillshade", alg = "ZevenbergenThorne", zFactor = 2, azimuth = 315, combined = False)
ds = None
src = PImage.open(tmpFile2)
grey = ImageOps.grayscale(src)
neg = ImageOps.invert(grey)
bands = neg.split()
black = PImage.new('RGBA', src.size)
black.putalpha(bands[0])
pixdata = black.load()
for y in range(black.size[1]):
    for x in range(black.size[0]):
        if pixdata[x, y] == (0, 0, 0, 255):
            pixdata[x, y] = (0, 0, 0, 0)
        else:
            a = pixdata[x, y]
            pixdata[x, y] =  a[:-1] + (a[-1]-74,)

blurRadius = 1
if blurRadius > 1:
    black = black.filter(ImageFilter.GaussianBlur(radius=blurRadius))

black.save(outfile)

os.remove(tmpFile1)
os.remove(tmpFile2)
