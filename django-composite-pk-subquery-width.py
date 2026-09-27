import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-composite-test",
    DATABASES={"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}},
    INSTALLED_APPS=[],
    USE_TZ=False,
)
django.setup()

from django.db import connection, models
from django.db.models import Subquery


class Token(models.Model):
    pk = models.CompositePrimaryKey("tenant_id", "id")
    tenant_id = models.IntegerField()
    id = models.IntegerField()
    secret = models.CharField(max_length=64)
    sort_key = models.CharField(max_length=64)

    class Meta:
        app_label = "h1test"
        db_table = "h1_token"


with connection.schema_editor() as editor:
    editor.create_model(Token)

rows = [
    Token(tenant_id=1, id=1, secret="tenant1-a", sort_key="z"),
    Token(tenant_id=1, id=2, secret="tenant1-b", sort_key="a"),
    Token(tenant_id=2, id=1, secret="tenant2-a", sort_key="m"),
    Token(tenant_id=2, id=2, secret="tenant2-b", sort_key="b"),
]
Token.objects.bulk_create(rows)


def pks(qs):
    return sorted(list(qs.values_list("tenant_id", "id")))


expected_t1 = [(1, 1), (1, 2)]
expected_t2 = [(2, 1), (2, 2)]

# Control: ordinary composite-pk subquery without DISTINCT/extra ORDER BY.
control_sub = Token.objects.filter(tenant_id=1).values("pk")
control = Token.objects.filter(pk__in=control_sub)
print("control SQL:", control.query)
print("control:", pks(control))
assert pks(control) == expected_t1

# Candidate: DISTINCT + ordering by an unselected field forces an extra SELECT
# inside a subquery. The wrapper at SQLCompiler.as_sql() must preserve both
# physical columns of CompositePrimaryKey.
sub = (
    Token.objects.filter(tenant_id=1)
    .values("pk")
    .distinct()
    .order_by("sort_key")
)
candidate = Token.objects.filter(pk__in=sub)
print("candidate subquery SQL:", sub.query)
print("candidate SQL:", candidate.query)
print("candidate:", pks(candidate))
assert pks(candidate) == expected_t1, pks(candidate)

excluded = Token.objects.exclude(pk__in=sub)
print("exclude:", pks(excluded))
assert pks(excluded) == expected_t2, pks(excluded)

# Explicit Subquery() follows a separate expression path.
explicit = Token.objects.filter(pk__in=Subquery(sub))
print("explicit Subquery:", pks(explicit))
assert pks(explicit) == expected_t1, pks(explicit)

# Exact lookup against one composite tuple selected through the same wrapped
# subquery. This is particularly relevant to object-level authorization.
one_sub = (
    Token.objects.filter(tenant_id=1, id=2)
    .values("pk")
    .distinct()
    .order_by("sort_key")[:1]
)
exact = Token.objects.filter(pk=Subquery(one_sub))
print("exact:", pks(exact))
assert pks(exact) == [(1, 2)], pks(exact)

# A fresh-ticket reproducer is included only as a sanity check that this build
# actually contains the known result-shaping fault line.
known = list(
    Token.objects.filter(tenant_id=1)
    .values_list("pk", flat=True)
    .distinct()
    .order_by("sort_key")
)
print("known direct values result:", known)

print("Django", django.get_version())
print("RESULT=SUBQUERY_WIDTH_SAFE")
