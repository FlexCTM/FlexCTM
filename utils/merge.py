#!/usr/bin/env python3
"""Concatenate FlexCTM snapshots along a time dimension for ncview."""

from __future__ import annotations

import argparse
from datetime import datetime
from glob import glob
import os
from pathlib import Path
import re
import sys
import tempfile

from netCDF4 import Dataset, date2num


TIME_PATTERN = re.compile(r"(?<!\d)(\d{14}|\d{12}|\d{10})(?!\d)")
TIME_FORMATS = {10: "%Y%m%d%H", 12: "%Y%m%d%H%M", 14: "%Y%m%d%H%M%S"}
WIND_VARIABLES = ("U", "V")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge FlexCTM snapshot files along a time dimension.",
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Input files or quoted glob patterns, for example 'ctm_d01_*.nc'.",
    )
    parser.add_argument("-o", "--output", required=True, help="Merged NetCDF file.")
    parser.add_argument(
        "-v",
        "--variable",
        action="append",
        dest="variables",
        help="Variable to retain; U and V are also retained when available.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace the output file if it already exists.",
    )
    return parser.parse_args()


def expand_inputs(patterns: list[str], output: Path) -> list[Path]:
    paths: set[Path] = set()
    output = output.resolve()
    for pattern in patterns:
        matches = glob(pattern)
        if not matches and Path(pattern).is_file():
            matches = [pattern]
        paths.update(Path(name).resolve() for name in matches)

    paths.discard(output)
    if not paths:
        raise ValueError("no input files matched")
    return sorted(paths)


def timestamp_from_name(path: Path) -> datetime | None:
    matches = TIME_PATTERN.findall(path.stem)
    if not matches:
        return None
    text = matches[-1]
    return datetime.strptime(text, TIME_FORMATS[len(text)])


def order_files(paths: list[Path]) -> tuple[list[Path], list[datetime] | None]:
    timestamps = [timestamp_from_name(path) for path in paths]
    if all(timestamp is None for timestamp in timestamps):
        return paths, None
    if any(timestamp is None for timestamp in timestamps):
        raise ValueError("timestamps were found in only some input filenames")

    pairs = sorted(zip(timestamps, paths), key=lambda item: item[0])
    ordered_times = [item[0] for item in pairs]
    if len(set(ordered_times)) != len(ordered_times):
        raise ValueError("input filenames contain duplicate timestamps")
    return [item[1] for item in pairs], ordered_times


def selected_variables(source: Dataset, requested: list[str] | None) -> list[str]:
    if requested:
        missing = [name for name in requested if name not in source.variables]
        if missing:
            raise ValueError(f"missing variables: {', '.join(missing)}")
        available_winds = [name for name in WIND_VARIABLES if name in source.variables]
        if available_winds and len(available_winds) != len(WIND_VARIABLES):
            raise ValueError("input contains only one of the required wind variables U and V")
        names = list(dict.fromkeys(requested + available_winds))
    else:
        names = list(source.variables)

    required_dimensions = {
        dimension
        for name in names
        for dimension in source.variables[name].dimensions
    }
    coordinate_names = [
        name
        for name in required_dimensions
        if name in source.variables and source.variables[name].dimensions == (name,)
    ]
    return list(dict.fromkeys(coordinate_names + names))


def copy_attributes(source, target) -> None:
    attributes = {
        name: source.getncattr(name)
        for name in source.ncattrs()
        if name != "_FillValue"
    }
    if attributes:
        target.setncatts(attributes)


def create_output(
    target: Dataset,
    source: Dataset,
    variable_names: list[str],
    timestamps: list[datetime] | None,
    snapshot_count: int,
) -> dict[str, bool]:
    if "time" in source.dimensions:
        raise ValueError("input files already contain a time dimension")

    target.createDimension("time", None)
    required_dimensions = {
        dimension
        for name in variable_names
        for dimension in source.variables[name].dimensions
    }
    for name in required_dimensions:
        if source.dimensions[name].isunlimited():
            raise ValueError(f'input dimension "{name}" must have a fixed size')
        target.createDimension(name, len(source.dimensions[name]))

    time = target.createVariable("time", "f8" if timestamps else "i4", ("time",))
    if timestamps:
        time.units = f"seconds since {timestamps[0]:%Y-%m-%d %H:%M:%S}"
        time.calendar = "proleptic_gregorian"
        time.standard_name = "time"
        time[:] = date2num(timestamps, units=time.units, calendar=time.calendar)
    else:
        time.long_name = "snapshot index"
        time[:] = list(range(snapshot_count))

    is_coordinate: dict[str, bool] = {}
    for name in variable_names:
        source_variable = source.variables[name]
        coordinate = source_variable.dimensions == (name,) and name in source.dimensions
        dimensions = (
            source_variable.dimensions
            if coordinate
            else ("time",) + source_variable.dimensions
        )
        options = {}
        if "_FillValue" in source_variable.ncattrs():
            options["fill_value"] = source_variable.getncattr("_FillValue")
        target_variable = target.createVariable(
            name, source_variable.datatype, dimensions, **options
        )
        copy_attributes(source_variable, target_variable)
        is_coordinate[name] = coordinate

    copy_attributes(source, target)
    return is_coordinate


def validate_snapshot(
    source: Dataset,
    reference: Dataset,
    variable_names: list[str],
    path: Path,
) -> None:
    for name in variable_names:
        if name not in source.variables:
            raise ValueError(f'{path}: missing variable "{name}"')
        variable = source.variables[name]
        reference_variable = reference.variables[name]
        if (
            variable.dimensions != reference_variable.dimensions
            or variable.shape != reference_variable.shape
        ):
            raise ValueError(f'{path}: variable "{name}" has incompatible dimensions')
        if variable.datatype != reference_variable.datatype:
            raise ValueError(f'{path}: variable "{name}" has an incompatible data type')


def stream_snapshots(
    paths: list[Path],
    timestamps: list[datetime] | None,
    variables: list[str] | None,
    output: Path,
) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with Dataset(paths[0], "r") as reference, Dataset(
            temporary, "w", format="NETCDF4"
        ) as target:
            variable_names = selected_variables(reference, variables)
            coordinate_flags = create_output(
                target, reference, variable_names, timestamps, len(paths)
            )
            for index, path in enumerate(paths):
                with Dataset(path, "r") as source:
                    validate_snapshot(source, reference, variable_names, path)
                    for name in variable_names:
                        if coordinate_flags[name]:
                            if index == 0:
                                target.variables[name][:] = source.variables[name][:]
                        else:
                            target.variables[name][index, ...] = source.variables[name][...]
        temporary.replace(output)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def main() -> int:
    args = parse_arguments()
    output = Path(args.output)
    try:
        paths = expand_inputs(args.inputs, output)
        paths, timestamps = order_files(paths)
        if output.exists() and not args.overwrite:
            raise ValueError(f'{output} already exists; use --overwrite to replace it')
        if not output.parent.exists():
            raise ValueError(f"output directory does not exist: {output.parent}")
        stream_snapshots(paths, timestamps, args.variables, output)
    except (OSError, RuntimeError, TypeError, ValueError, KeyError) as error:
        print(f"merge.py: {error}", file=sys.stderr)
        return 2

    print(f"Merged {len(paths)} snapshots into {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
